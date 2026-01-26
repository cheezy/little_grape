defmodule LittleGrape.Discovery do
  @moduledoc """
  The Discovery context.

  Provides composable query functions for filtering users in the discovery feed.
  These "hard filters" exclude users who should never appear in a user's feed:
  - Users already swiped on
  - The user themselves
  - Blocked users (both directions)
  - Users with incomplete profiles
  - Users who don't match gender preferences (bidirectional)
  """

  import Ecto.Query, warn: false

  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Accounts.User
  alias LittleGrape.Blocks.Block
  alias LittleGrape.Swipes.Swipe

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
end
