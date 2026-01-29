defmodule LittleGrape.Matches do
  @moduledoc """
  The Matches context.
  """

  alias Ecto.Multi
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
end
