defmodule LittleGrape.Swipes do
  @moduledoc """
  The Swipes context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias LittleGrape.Accounts.User
  alias LittleGrape.Matches
  alias LittleGrape.Repo
  alias LittleGrape.Swipes.Swipe

  @doc """
  Records a swipe and, when it completes a reciprocal like, creates the match
  and its conversation — all in a single transaction.

  This is the orchestration entry point callers should use instead of chaining
  `create_swipe/3`, `check_for_match/2`, and `Matches.create_match/2`. When two
  users like each other near-simultaneously and both transactions race on the
  matches unique index, the loser resolves to the existing match instead of
  failing, and only the transaction that actually inserted the match broadcasts
  `:new_match`.

  ## Parameters

    * `user` - The user performing the swipe (struct with id) — always taken
      from the authenticated session, never from client params
    * `target_user_id` - The ID of the user being swiped on
    * `action` - Either "like" or "pass"

  ## Returns

    * `{:ok, :no_match}` - Swipe recorded, no reciprocal like
    * `{:ok, {:match, %Match{}}}` - Mutual like; the match was created (or
      already existed and was resolved)
    * `{:error, %Ecto.Changeset{}}` - Invalid action, duplicate swipe, or
      missing target

  ## Examples

      iex> swipe(user, target_id, "like")
      {:ok, :no_match}

      iex> swipe(user, reciprocal_liker_id, "like")
      {:ok, {:match, %Match{}}}

      iex> swipe(user, target_id, "invalid")
      {:error, %Ecto.Changeset{}}

  """
  def swipe(%User{id: user_id}, target_user_id, action) do
    Multi.new()
    |> Multi.insert(
      :swipe,
      Swipe.changeset(%Swipe{}, %{
        user_id: user_id,
        target_user_id: target_user_id,
        action: action
      })
    )
    |> Multi.merge(fn %{swipe: swipe} ->
      if swipe.action == "like" and check_for_match(user_id, target_user_id) do
        Matches.match_multi(user_id, target_user_id)
      else
        Multi.new()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{match: {:created, match}}} ->
        Matches.broadcast_new_match(match)
        {:ok, {:match, match}}

      {:ok, %{match: {:existing, match}}} ->
        {:ok, {:match, match}}

      {:ok, _swipe_only} ->
        {:ok, :no_match}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Creates a swipe record for a user swiping on another user.

  Prefer `swipe/3` for the full swipe-to-match orchestration; this function
  only inserts the swipe row.

  ## Parameters

    * `user` - The user performing the swipe (struct with id)
    * `target_user_id` - The ID of the user being swiped on
    * `action` - Either "like" or "pass"

  ## Returns

    * `{:ok, %Swipe{}}` - Successfully created swipe
    * `{:error, %Ecto.Changeset{}}` - Validation or constraint error

  ## Examples

      iex> create_swipe(user, target_id, "like")
      {:ok, %Swipe{}}

      iex> create_swipe(user, target_id, "invalid")
      {:error, %Ecto.Changeset{}}

      iex> create_swipe(user, same_target_id, "like") # duplicate
      {:error, %Ecto.Changeset{}}

  """
  def create_swipe(%User{id: user_id}, target_user_id, action) do
    %Swipe{}
    |> Swipe.changeset(%{
      user_id: user_id,
      target_user_id: target_user_id,
      action: action
    })
    |> Repo.insert()
  end

  @doc """
  Gets a swipe by user and target user.

  ## Examples

      iex> get_swipe(user_id, target_user_id)
      %Swipe{}

      iex> get_swipe(user_id, non_existent_target_id)
      nil

  """
  def get_swipe(user_id, target_user_id) do
    Repo.get_by(Swipe, user_id: user_id, target_user_id: target_user_id)
  end

  @doc """
  Checks if a user has already swiped on a target user.

  ## Examples

      iex> has_swiped?(user_id, target_user_id)
      true

      iex> has_swiped?(user_id, new_target_user_id)
      false

  """
  def has_swiped?(user_id, target_user_id) do
    query =
      from s in Swipe,
        where: s.user_id == ^user_id and s.target_user_id == ^target_user_id

    Repo.exists?(query)
  end

  @doc """
  Checks if the target user has liked the current user back (reciprocal like).

  This is used to detect matches - when both users have liked each other.
  Only considers 'like' actions, not 'pass'.

  ## Examples

      iex> check_for_match(user_id, target_user_id)
      true  # Target has liked user back

      iex> check_for_match(user_id, target_who_passed)
      false  # Target passed, not liked

  """
  def check_for_match(user_id, target_user_id) do
    query =
      from s in Swipe,
        where:
          s.user_id == ^target_user_id and
            s.target_user_id == ^user_id and
            s.action == "like"

    Repo.exists?(query)
  end

  @doc """
  Lists the target user IDs that the given user previously passed on,
  most recently passed first.
  """
  def list_passed_target_ids(%User{id: user_id}) do
    from(s in Swipe,
      where: s.user_id == ^user_id and s.action == "pass",
      order_by: [desc: s.inserted_at, desc: s.id],
      select: s.target_user_id
    )
    |> Repo.all()
  end

  @doc """
  Deletes a "pass" swipe so the target user can re-enter the discovery feed.

  Only deletes swipes with action `"pass"` — likes cannot be removed this way.

  ## Returns

    * `{:ok, %Swipe{}}` — the deleted swipe
    * `{:error, :not_found}` — no matching pass swipe exists
  """
  def delete_pass(%User{id: user_id}, target_user_id) do
    case Repo.get_by(Swipe, user_id: user_id, target_user_id: target_user_id, action: "pass") do
      nil -> {:error, :not_found}
      swipe -> Repo.delete(swipe)
    end
  end
end
