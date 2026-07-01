defmodule LittleGrape.Matches do
  @moduledoc """
  The Matches context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias LittleGrape.Accounts.User
  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging
  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Repo

  @doc """
  Creates a match and associated conversation in a single transaction.

  Normalizes user IDs so that user_a_id < user_b_id for consistent ordering.

  ## Parameters

    * `user_a_id` - ID of one user in the match
    * `user_b_id` - ID of the other user in the match

  ## Returns

    * `{:ok, %{match: %Match{}, conversation: %Conversation{}}}` - Success. When
      the match already existed (duplicate attempt or concurrent creation), the
      existing match and conversation are returned and no broadcast is fired.
    * `{:error, %Ecto.Changeset{}}` - Match or conversation creation failed

  ## Examples

      iex> create_match(1, 2)
      {:ok, %{match: %Match{}, conversation: %Conversation{}}}

      iex> create_match(2, 1)  # IDs are normalized
      {:ok, %{match: %Match{user_a_id: 1, user_b_id: 2}, conversation: %Conversation{}}}

      iex> create_match(1, 2)  # duplicate attempt resolves to the existing match
      {:ok, %{match: %Match{}, conversation: %Conversation{}}}

  """
  def create_match(user_a_id, user_b_id) do
    match_multi(user_a_id, user_b_id)
    |> Repo.transaction()
    |> case do
      {:ok, %{match: {:created, match}, conversation: conversation}} ->
        broadcast_new_match(match)
        {:ok, %{match: match, conversation: conversation}}

      {:ok, %{match: {:existing, match}, conversation: conversation}} ->
        {:ok, %{match: match, conversation: conversation}}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns an `Ecto.Multi` that inserts a match and its conversation, resolving
  a unique-index collision (the match already exists) to the existing records.

  Steps: `:match_insert` (insert with `on_conflict: :nothing`), `:match`
  (returns `{:created, match}` or `{:existing, match}`), and `:conversation`.

  Does NOT broadcast — the caller must broadcast after commit, and only when
  the `:match` step returns `{:created, match}`, so the broadcast fires exactly
  once per match (only from the transaction that actually inserted it).
  """
  def match_multi(user_a_id, user_b_id) do
    {normalized_a, normalized_b} = Match.normalize_user_ids(user_a_id, user_b_id)

    Multi.new()
    |> Multi.insert(
      :match_insert,
      Match.changeset(%Match{}, %{
        user_a_id: normalized_a,
        user_b_id: normalized_b,
        matched_at: DateTime.utc_now()
      }),
      on_conflict: :nothing,
      conflict_target: [:user_a_id, :user_b_id]
    )
    |> Multi.run(:match, fn repo, %{match_insert: inserted} ->
      if inserted.id do
        {:ok, {:created, inserted}}
      else
        case repo.get_by(Match, user_a_id: normalized_a, user_b_id: normalized_b) do
          nil -> {:error, :match_vanished}
          match -> {:ok, {:existing, match}}
        end
      end
    end)
    |> Multi.run(:conversation, fn repo, %{match: match_result} ->
      case match_result do
        {:created, match} ->
          %Conversation{}
          |> Conversation.changeset(%{match_id: match.id})
          |> repo.insert()

        {:existing, match} ->
          {:ok, repo.get_by(Conversation, match_id: match.id)}
      end
    end)
  end

  @doc false
  def broadcast_new_match(match) do
    Phoenix.PubSub.broadcast(LittleGrape.PubSub, "user:#{match.user_a_id}", {:new_match, match})
    Phoenix.PubSub.broadcast(LittleGrape.PubSub, "user:#{match.user_b_id}", {:new_match, match})
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

  @doc """
  Removes a match and its associated conversation and messages.

  Only succeeds if the user is a participant in the match (user_a or user_b).
  The database cascade delete will automatically remove the conversation and
  any messages when the match is deleted.

  ## Parameters

    * `user` - The user struct with an id
    * `match_id` - The ID of the match to remove

  ## Returns

    * `:ok` if the match was deleted successfully
    * `{:error, :not_found}` if the match doesn't exist or user is not a participant

  ## Examples

      iex> unmatch(participant_user, match_id)
      :ok

      iex> unmatch(non_participant_user, match_id)
      {:error, :not_found}

      iex> unmatch(user, non_existent_id)
      {:error, :not_found}

  """
  def unmatch(%User{} = user, match_id) do
    case get_match(user, match_id) do
      nil ->
        {:error, :not_found}

      match ->
        Repo.delete(match)
        :ok
    end
  end

  @doc """
  Lists all matches for a user with details needed for display.

  Returns matches with preloaded user profiles, last message preview, and unread counts.
  Results are ordered with new matches (no messages) first, then by most recent message.

  ## Parameters

    * `user` - The user struct with an id

  ## Returns

    * List of maps with `:match`, `:other_user`, `:other_profile`, `:last_message`,
      `:unread_count`, and `:is_new_match` keys

  ## Examples

      iex> list_matches_with_details(user)
      [
        %{
          match: %Match{},
          other_user: %User{},
          other_profile: %Profile{},
          last_message: %Message{} | nil,
          unread_count: 3,
          is_new_match: false
        }
      ]

  """
  def list_matches_with_details(%User{id: user_id}) do
    matches = fetch_matches_with_preloads(user_id)
    conversation_ids = conversation_ids(matches)
    unread_counts = Messaging.unread_counts_for_conversations(conversation_ids, user_id)
    last_messages = Messaging.last_messages_for_conversations(conversation_ids)

    matches
    |> Enum.map(&build_match_details(&1, user_id, unread_counts, last_messages))
    |> sort_matches_by_priority()
  end

  defp fetch_matches_with_preloads(user_id) do
    from(m in Match,
      where: m.user_a_id == ^user_id or m.user_b_id == ^user_id,
      preload: [:conversation, user_a: :profile, user_b: :profile],
      order_by: [desc: m.matched_at]
    )
    |> Repo.all()
  end

  defp conversation_ids(matches) do
    matches
    |> Enum.map(& &1.conversation)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.id)
  end

  defp build_match_details(match, user_id, unread_counts, last_messages) do
    other_user = get_other_user(match, user_id)
    last_message = get_last_message(match, last_messages)

    %{
      match: match,
      other_user: other_user,
      other_profile: other_user.profile,
      last_message: last_message,
      unread_count: get_unread_count(match, unread_counts),
      is_new_match: is_nil(last_message)
    }
  end

  defp get_other_user(match, user_id) do
    if match.user_a_id == user_id, do: match.user_b, else: match.user_a
  end

  defp get_last_message(%{conversation: nil}, _last_messages), do: nil

  defp get_last_message(%{conversation: conv}, last_messages),
    do: Map.get(last_messages, conv.id)

  defp get_unread_count(%{conversation: nil}, _unread_counts), do: 0

  defp get_unread_count(%{conversation: conv}, unread_counts),
    do: Map.get(unread_counts, conv.id, 0)

  defp sort_matches_by_priority(match_details) do
    Enum.sort_by(
      match_details,
      fn %{is_new_match: is_new_match, match: match, last_message: last_message} ->
        activity_time = (last_message && last_message.inserted_at) || match.matched_at
        {not is_new_match, activity_time}
      end,
      &compare_match_priority/2
    )
  end

  defp compare_match_priority({is_not_new, time}, {is_not_new2, time2}) do
    if is_not_new == is_not_new2 do
      DateTime.compare(time2, time) != :lt
    else
      not is_not_new
    end
  end
end
