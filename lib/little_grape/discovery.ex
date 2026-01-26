defmodule LittleGrape.Discovery do
  @moduledoc """
  The Discovery context.

  Provides composable query functions for filtering users in the discovery feed.

  ## Hard Filters
  These "hard filters" exclude users who should never appear in a user's feed:
  - Users already swiped on
  - The user themselves
  - Blocked users (both directions)
  - Users with incomplete profiles
  - Users who don't match gender preferences (bidirectional)

  ## Soft Scoring
  After hard filtering, candidates are scored based on compatibility factors:
  - Age range match: 30%
  - Country match: 20%
  - Shared interests: 20%
  - Shared languages: 10%
  - Religion alignment: 10%
  - Profile freshness: 5%
  - Liked-you boost: 5%
  - Randomization: +/-10% variance
  """

  import Ecto.Query, warn: false

  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Accounts.User
  alias LittleGrape.Blocks.Block
  alias LittleGrape.Repo
  alias LittleGrape.Swipes.Swipe

  # Scoring weights
  @age_weight 0.30
  @country_weight 0.20
  @interests_weight 0.20
  @languages_weight 0.10
  @religion_weight 0.10
  @freshness_weight 0.05
  @liked_you_weight 0.05
  @randomization_variance 0.10

  @doc """
  Returns a base query for users that can be filtered further.
  """
  def base_query do
    from(u in User, as: :user)
  end

  @doc """
  Excludes the current user from the query results.

  ## Examples

      iex> base_query() |> exclude_self(user_id)
      #Ecto.Query<...>

  """
  def exclude_self(query, user_id) do
    from [user: u] in query,
      where: u.id != ^user_id
  end

  @doc """
  Excludes users that the current user has already swiped on (liked or passed).

  ## Examples

      iex> base_query() |> exclude_already_swiped(user_id)
      #Ecto.Query<...>

  """
  def exclude_already_swiped(query, user_id) do
    from [user: u] in query,
      where:
        u.id not in subquery(
          from s in Swipe,
            where: s.user_id == ^user_id,
            select: s.target_user_id
        )
  end

  @doc """
  Excludes users that are blocked in either direction.
  - Users that the current user has blocked
  - Users that have blocked the current user

  ## Examples

      iex> base_query() |> exclude_blocked(user_id)
      #Ecto.Query<...>

  """
  def exclude_blocked(query, user_id) do
    # Users blocked by current user
    blocked_by_me =
      from b in Block,
        where: b.blocker_id == ^user_id,
        select: b.blocked_id

    # Users who blocked current user
    blocked_me =
      from b in Block,
        where: b.blocked_id == ^user_id,
        select: b.blocker_id

    from [user: u] in query,
      where: u.id not in subquery(blocked_by_me),
      where: u.id not in subquery(blocked_me)
  end

  @doc """
  Excludes users with incomplete profiles.
  A profile is considered incomplete if it's missing any of:
  - profile_picture
  - first_name
  - birthdate
  - gender

  ## Examples

      iex> base_query() |> require_complete_profile()
      #Ecto.Query<...>

  """
  def require_complete_profile(query) do
    from [user: u] in query,
      join: p in Profile,
      on: p.user_id == u.id,
      as: :profile,
      where: not is_nil(p.profile_picture),
      where: not is_nil(p.first_name),
      where: not is_nil(p.birthdate),
      where: not is_nil(p.gender)
  end

  @doc """
  Filters users by mutual gender preferences.
  Both conditions must be met:
  1. The candidate's gender matches what the current user is looking for
  2. The current user's gender matches what the candidate is looking for

  The special value 'any' matches all genders.

  ## Parameters

    * `query` - The query to filter
    * `user_gender` - The current user's gender
    * `user_preferred_gender` - The current user's preferred gender (can be 'any')

  ## Examples

      iex> base_query()
      ...> |> require_complete_profile()
      ...> |> filter_by_mutual_gender_preferences("male", "female")
      #Ecto.Query<...>

  """
  def filter_by_mutual_gender_preferences(query, user_gender, user_preferred_gender) do
    query
    |> filter_candidate_matches_user_preference(user_preferred_gender)
    |> filter_user_matches_candidate_preference(user_gender)
  end

  # Filter: candidate's gender matches what current user is looking for
  defp filter_candidate_matches_user_preference(query, "any") do
    # User is open to any gender - no filtering needed
    query
  end

  defp filter_candidate_matches_user_preference(query, preferred_gender) do
    from [profile: p] in query,
      where: p.gender == ^preferred_gender
  end

  # Filter: current user's gender matches what candidate is looking for
  defp filter_user_matches_candidate_preference(query, user_gender) do
    from [profile: p] in query,
      where: p.preferred_gender == "any" or p.preferred_gender == ^user_gender
  end

  @doc """
  Applies all hard filters for discovery.
  This is a convenience function that chains all filter functions together.

  ## Parameters

    * `user` - The current user (must have profile preloaded with gender and preferred_gender)

  ## Returns

    A query that excludes:
    - The user themselves
    - Users already swiped on
    - Blocked users (both directions)
    - Users with incomplete profiles
    - Users who don't match gender preferences

  ## Examples

      iex> user = %User{id: 1, profile: %Profile{gender: "male", preferred_gender: "female"}}
      iex> apply_hard_filters(user)
      #Ecto.Query<...>

  """
  def apply_hard_filters(%User{id: user_id, profile: profile}) do
    user_gender = profile.gender
    user_preferred_gender = profile.preferred_gender

    base_query()
    |> exclude_self(user_id)
    |> exclude_already_swiped(user_id)
    |> exclude_blocked(user_id)
    |> require_complete_profile()
    |> filter_by_mutual_gender_preferences(user_gender, user_preferred_gender)
  end

  # ============================================================================
  # Soft Scoring Functions
  # ============================================================================

  @doc """
  Calculates the age score based on how well the candidate's age matches
  the user's preferred age range.

  Returns a score between 0.0 and 1.0:
  - 1.0 if candidate's age is within the user's preferred range
  - 0.5-1.0 if within 5 years of the range
  - 0.0-0.5 if further away

  If the user has no age preference (nil), returns 1.0 (no penalty).

  ## Parameters
    * `candidate_birthdate` - The candidate's birthdate
    * `preferred_age_min` - User's minimum preferred age (nil means no minimum)
    * `preferred_age_max` - User's maximum preferred age (nil means no maximum)
  """
  def score_age(nil, _min, _max), do: 0.0

  def score_age(candidate_birthdate, preferred_age_min, preferred_age_max) do
    candidate_age = calculate_age(candidate_birthdate)

    min_age = preferred_age_min || 18
    max_age = preferred_age_max || 100

    cond do
      candidate_age >= min_age and candidate_age <= max_age ->
        1.0

      candidate_age < min_age ->
        diff = min_age - candidate_age
        max(0.0, 1.0 - diff * 0.1)

      candidate_age > max_age ->
        diff = candidate_age - max_age
        max(0.0, 1.0 - diff * 0.1)
    end
  end

  @doc """
  Calculates the country match score.

  Returns 1.0 if countries match, 0.0 otherwise.
  If either country is nil, returns 0.5 (neutral).
  """
  def score_country(nil, _), do: 0.5
  def score_country(_, nil), do: 0.5

  def score_country(user_country, candidate_country) when user_country == candidate_country,
    do: 1.0

  def score_country(_, _), do: 0.0

  @doc """
  Calculates the shared interests score.

  Returns a score between 0.0 and 1.0 based on the proportion
  of interests that are shared between user and candidate.

  If either has no interests, returns 0.5 (neutral).
  """
  def score_interests(nil, _), do: 0.5
  def score_interests(_, nil), do: 0.5
  def score_interests([], _), do: 0.5
  def score_interests(_, []), do: 0.5

  def score_interests(user_interests, candidate_interests) do
    user_set = MapSet.new(user_interests)
    candidate_set = MapSet.new(candidate_interests)

    shared_count = MapSet.intersection(user_set, candidate_set) |> MapSet.size()
    total_unique = MapSet.union(user_set, candidate_set) |> MapSet.size()

    if total_unique == 0 do
      0.5
    else
      shared_count / total_unique
    end
  end

  @doc """
  Calculates the shared languages score.

  Returns a score between 0.0 and 1.0 based on whether users share
  any common languages.

  If either has no languages, returns 0.5 (neutral).
  """
  def score_languages(nil, _), do: 0.5
  def score_languages(_, nil), do: 0.5
  def score_languages([], _), do: 0.5
  def score_languages(_, []), do: 0.5

  def score_languages(user_languages, candidate_languages) do
    user_set = MapSet.new(user_languages)
    candidate_set = MapSet.new(candidate_languages)

    shared = MapSet.intersection(user_set, candidate_set)

    cond do
      MapSet.size(shared) >= 2 -> 1.0
      MapSet.size(shared) == 1 -> 0.75
      true -> 0.0
    end
  end

  @doc """
  Calculates the religion alignment score.

  Returns a score between 0.0 and 1.0:
  - 1.0 if religions match
  - 0.5 if either party prefers not to say (neutral)
  - 0.0 if religions don't match
  """
  def score_religion(nil, _), do: 0.5
  def score_religion(_, nil), do: 0.5
  def score_religion("prefer_not_to_say", _), do: 0.5
  def score_religion(_, "prefer_not_to_say"), do: 0.5

  def score_religion(user_religion, candidate_religion) when user_religion == candidate_religion,
    do: 1.0

  def score_religion(_, _), do: 0.0

  @doc """
  Calculates the profile freshness score.

  Returns a score between 0.0 and 1.0 based on how recently
  the candidate's profile was updated.

  - 1.0 if updated within the last day
  - Decays linearly over 30 days
  - 0.0 if not updated in 30+ days
  """
  def score_freshness(nil), do: 0.5

  def score_freshness(updated_at) do
    now = DateTime.utc_now()
    days_old = DateTime.diff(now, updated_at, :day)

    cond do
      days_old <= 1 -> 1.0
      days_old >= 30 -> 0.0
      true -> 1.0 - days_old / 30.0
    end
  end

  @doc """
  Calculates the liked-you boost score.

  Returns 1.0 if the candidate has liked the user, 0.0 otherwise.
  This encourages showing users who have already expressed interest.
  """
  def score_liked_you(has_liked_you) when is_boolean(has_liked_you) do
    if has_liked_you, do: 1.0, else: 0.0
  end

  def score_liked_you(_), do: 0.0

  @doc """
  Adds randomization to prevent deterministic ordering.

  Returns a random value between -@randomization_variance and +@randomization_variance.
  """
  def random_variance do
    (:rand.uniform() - 0.5) * 2 * @randomization_variance
  end

  @doc """
  Calculates the composite compatibility score for a candidate.

  ## Parameters
    * `user_profile` - The current user's profile
    * `candidate_profile` - The candidate's profile
    * `has_liked_user` - Boolean indicating if candidate has liked the user

  ## Returns
    A score between 0.0 and 1.0 (plus/minus randomization variance)
  """
  def calculate_score(user_profile, candidate_profile, has_liked_user \\ false) do
    age_score =
      score_age(
        candidate_profile.birthdate,
        user_profile.preferred_age_min,
        user_profile.preferred_age_max
      )

    country_score = score_country(user_profile.country, candidate_profile.country)
    interests_score = score_interests(user_profile.interests, candidate_profile.interests)
    languages_score = score_languages(user_profile.languages, candidate_profile.languages)
    religion_score = score_religion(user_profile.religion, candidate_profile.religion)
    freshness_score = score_freshness(candidate_profile.updated_at)
    liked_you_score = score_liked_you(has_liked_user)

    base_score =
      age_score * @age_weight +
        country_score * @country_weight +
        interests_score * @interests_weight +
        languages_score * @languages_weight +
        religion_score * @religion_weight +
        freshness_score * @freshness_weight +
        liked_you_score * @liked_you_weight

    # Add randomization and clamp to [0, 1]
    (base_score + random_variance())
    |> max(0.0)
    |> min(1.0)
  end

  @doc """
  Scores and ranks candidates for a user's discovery feed.

  Takes a query of filtered candidates and returns them sorted by compatibility score.

  ## Parameters
    * `user` - The current user with profile preloaded
    * `query` - A query of filtered candidates (usually from apply_hard_filters/1)

  ## Returns
    A list of `{user, score}` tuples sorted by score descending
  """
  def score_and_rank(%User{id: user_id, profile: user_profile}, query) do
    # Get all candidate users with their profiles
    candidates =
      query
      |> Repo.all()
      |> Repo.preload(:profile)

    # Get the set of users who have liked the current user
    liked_user_ids =
      from(s in Swipe,
        where: s.target_user_id == ^user_id and s.action == "like",
        select: s.user_id
      )
      |> Repo.all()
      |> MapSet.new()

    # Score each candidate
    candidates
    |> Enum.map(fn candidate ->
      has_liked_user = MapSet.member?(liked_user_ids, candidate.id)
      score = calculate_score(user_profile, candidate.profile, has_liked_user)
      {candidate, score}
    end)
    |> Enum.sort_by(fn {_candidate, score} -> score end, :desc)
  end

  @doc """
  Returns the discovery feed for a user.

  Applies hard filters, scores candidates, and returns them ranked
  by compatibility score.

  ## Parameters
    * `user` - The current user with profile preloaded

  ## Options
    * `:limit` - Maximum number of candidates to return (default: 50)

  ## Returns
    A list of user structs sorted by compatibility score
  """
  def get_discovery_feed(%User{} = user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    query = apply_hard_filters(user)

    user
    |> score_and_rank(query)
    |> Enum.take(limit)
    |> Enum.map(fn {candidate, _score} -> candidate end)
  end

  @doc """
  Returns ranked candidate profiles for a user's discovery feed.

  This is the main public API for discovery. It combines hard filters,
  soft scoring, and returns profiles ordered by compatibility.

  ## Parameters
    * `user` - The current user with profile preloaded
    * `limit` - Maximum number of profiles to return (default: 20)

  ## Returns
    A list of Profile structs sorted by compatibility score descending.
    Returns an empty list when no candidates are available.

  ## Examples

      iex> user = %User{id: 1, profile: %Profile{gender: "male", preferred_gender: "female"}}
      iex> get_candidates(user)
      [%Profile{}, %Profile{}, ...]

      iex> get_candidates(user, 10)
      [%Profile{}, ...]

  """
  def get_candidates(%User{} = user, limit \\ 20) do
    query = apply_hard_filters(user)

    user
    |> score_and_rank(query)
    |> Enum.take(limit)
    |> Enum.map(fn {candidate, _score} -> candidate.profile end)
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp calculate_age(birthdate) do
    today = Date.utc_today()
    years = today.year - birthdate.year

    # Check if birthday hasn't occurred yet this year
    birthday_this_year = Date.new!(today.year, birthdate.month, birthdate.day)

    case Date.compare(birthday_this_year, today) do
      :gt -> years - 1
      _ -> years
    end
  end
end
