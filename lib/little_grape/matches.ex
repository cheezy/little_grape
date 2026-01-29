defmodule LittleGrape.Matches do
  @moduledoc """
  The Matches context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias LittleGrape.Accounts.User
  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Repo

  @doc """
  Creates a match and associated conversation in a single transaction.

  Normalizes user IDs so that user_a_id < user_b_id for consistent ordering.

  ## Parameters

    * `user_a_id` - ID of one user in the match
    * `user_b_id` - ID of the other user in the match

  ## Returns

    * `{:ok, %{match: %Match{}, conversation: %Conversation{}}}` - Success
    * `{:error, :match, %Ecto.Changeset{}, %{}}` - Match creation failed
    * `{:error, :conversation, %Ecto.Changeset{}, %{}}` - Conversation creation failed

  ## Examples

      iex> create_match(1, 2)
      {:ok, %{match: %Match{}, conversation: %Conversation{}}}

      iex> create_match(2, 1)  # IDs are normalized
      {:ok, %{match: %Match{user_a_id: 1, user_b_id: 2}, conversation: %Conversation{}}}

      iex> create_match(1, 2)  # duplicate attempt
      {:error, :match, %Ecto.Changeset{}, %{}}

  """
  def create_match(user_a_id, user_b_id) do
    {normalized_a, normalized_b} = Match.normalize_user_ids(user_a_id, user_b_id)

    Multi.new()
    |> Multi.insert(:match, fn _changes ->
      Match.changeset(%Match{}, %{
        user_a_id: normalized_a,
        user_b_id: normalized_b,
        matched_at: DateTime.utc_now()
      })
    end)
    |> Multi.insert(:conversation, fn %{match: match} ->
      Conversation.changeset(%Conversation{}, %{match_id: match.id})
    end)
    |> Repo.transaction()
  end

  @doc """
  Lists all matches for a user.

  Returns matches where the user is either user_a or user_b.

  ## Parameters

    * `user` - The user struct with an id

  ## Returns

    * List of `%Match{}` structs

  ## Examples

      iex> list_matches(user)
      [%Match{}, %Match{}]

      iex> list_matches(user_with_no_matches)
      []

  """
  def list_matches(%User{id: user_id}) do
    from(m in Match,
      where: m.user_a_id == ^user_id or m.user_b_id == ^user_id,
      order_by: [desc: m.matched_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a specific match by ID, with authorization check.

  Returns the match only if the user is a participant (user_a or user_b).
  Returns nil if the match doesn't exist or the user is not a participant.

  ## Parameters

    * `user` - The user struct with an id
    * `match_id` - The ID of the match to retrieve

  ## Returns

    * `%Match{}` if found and user is participant
    * `nil` if not found or unauthorized

  ## Examples

      iex> get_match(participant_user, match_id)
      %Match{}

      iex> get_match(non_participant_user, match_id)
      nil

      iex> get_match(user, non_existent_id)
      nil

  """
  def get_match(%User{id: user_id}, match_id) do
    from(m in Match,
      where: m.id == ^match_id,
      where: m.user_a_id == ^user_id or m.user_b_id == ^user_id
    )
    |> Repo.one()
  end
end
