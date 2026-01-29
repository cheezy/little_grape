defmodule LittleGrape.Messaging do
  @moduledoc """
  The Messaging context.
  """

  import Ecto.Query, warn: false

  alias LittleGrape.Accounts.User
  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Messaging.Message
  alias LittleGrape.Repo

  @doc """
  Creates a message in a conversation.

  ## Parameters

    * `conversation_id` - The ID of the conversation
    * `sender_id` - The ID of the user sending the message
    * `content` - The message content

  ## Returns

    * `{:ok, %Message{}}` - Successfully created message
    * `{:error, %Ecto.Changeset{}}` - Validation error

  ## Examples

      iex> create_message(conversation_id, sender_id, "Hello!")
      {:ok, %Message{}}

  """
  def create_message(conversation_id, sender_id, content) do
    result =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation_id,
        sender_id: sender_id,
        content: content
      })
      |> Repo.insert()

    case result do
      {:ok, message} = success ->
        broadcast_new_message(conversation_id, message)
        success

      error ->
        error
    end
  end

  defp broadcast_new_message(conversation_id, message) do
    conversation =
      Repo.get(Conversation, conversation_id)
      |> Repo.preload(:match)

    if conversation && conversation.match do
      match = conversation.match

      Phoenix.PubSub.broadcast(
        LittleGrape.PubSub,
        "user:#{match.user_a_id}",
        {:new_message, message}
      )

      Phoenix.PubSub.broadcast(
        LittleGrape.PubSub,
        "user:#{match.user_b_id}",
        {:new_message, message}
      )
    end
  end

  @doc """
  Counts unread messages in a conversation for a specific user.

  A message is considered unread if:
  - It was sent by someone other than the user
  - It has a nil read_at timestamp

  ## Parameters

    * `conversation_id` - The ID of the conversation
    * `user_id` - The ID of the user checking for unread messages

  ## Returns

    * Integer count of unread messages

  ## Examples

      iex> unread_count(conversation_id, user_id)
      3

  """
  def unread_count(conversation_id, user_id) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      where: m.sender_id != ^user_id,
      where: is_nil(m.read_at),
      select: count(m.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets unread message counts for multiple conversations in a single query.

  Efficiently retrieves unread counts for all conversations at once to avoid N+1 queries.

  ## Parameters

    * `conversation_ids` - List of conversation IDs
    * `user_id` - The ID of the user checking for unread messages

  ## Returns

    * Map of conversation_id => unread_count

  ## Examples

      iex> unread_counts_for_conversations([1, 2, 3], user_id)
      %{1 => 2, 2 => 0, 3 => 5}

  """
  def unread_counts_for_conversations(conversation_ids, user_id) when is_list(conversation_ids) do
    from(m in Message,
      where: m.conversation_id in ^conversation_ids,
      where: m.sender_id != ^user_id,
      where: is_nil(m.read_at),
      group_by: m.conversation_id,
      select: {m.conversation_id, count(m.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets a conversation for a match, with authorization check.

  Returns the conversation only if the user is a participant in the match
  (either user_a or user_b).

  ## Parameters

    * `user` - The user struct with an id
    * `match_id` - The ID of the match to get the conversation for

  ## Returns

    * `{:ok, %Conversation{}}` if found and user is participant
    * `{:error, :not_found}` if not found or unauthorized

  ## Examples

      iex> get_conversation(participant_user, match_id)
      {:ok, %Conversation{}}

      iex> get_conversation(non_participant_user, match_id)
      {:error, :not_found}

  """
  def get_conversation(%User{id: user_id}, match_id) do
    conversation =
      from(c in Conversation,
        join: m in Match,
        on: c.match_id == m.id,
        where: m.id == ^match_id,
        where: m.user_a_id == ^user_id or m.user_b_id == ^user_id,
        select: c
      )
      |> Repo.one()

    case conversation do
      nil -> {:error, :not_found}
      conv -> {:ok, conv}
    end
  end

  @doc """
  Lists messages in a conversation with pagination support.

  Messages are ordered by inserted_at ascending (oldest first).

  ## Parameters

    * `conversation` - The conversation struct or conversation id
    * `opts` - Keyword list of options:
      * `:limit` - Maximum number of messages to return (default: 50)
      * `:offset` - Number of messages to skip (default: 0)

  ## Returns

    * List of `%Message{}` structs ordered by inserted_at ascending

  ## Examples

      iex> list_messages(conversation)
      [%Message{}, %Message{}]

      iex> list_messages(conversation, limit: 10, offset: 20)
      [%Message{}, ...]

  """
  def list_messages(conversation, opts \\ [])

  def list_messages(%Conversation{id: conversation_id}, opts) do
    list_messages(conversation_id, opts)
  end

  def list_messages(conversation_id, opts) when is_integer(conversation_id) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [asc: m.inserted_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Sends a message in a conversation with authorization check.

  Verifies that the user is a participant in the conversation (via match relationship)
  before creating the message. Broadcasts to both user topics and conversation topic.

  ## Parameters

    * `user` - The user struct sending the message
    * `conversation_id` - The ID of the conversation
    * `content` - The message content (1-2000 characters)

  ## Returns

    * `{:ok, %Message{}}` - Successfully sent message
    * `{:error, :not_authorized}` - User is not a participant in the conversation
    * `{:error, %Ecto.Changeset{}}` - Validation error

  ## Examples

      iex> send_message(user, conversation_id, "Hello!")
      {:ok, %Message{}}

      iex> send_message(non_participant, conversation_id, "Hello!")
      {:error, :not_authorized}

  """
  def send_message(%User{id: user_id} = _user, conversation_id, content) do
    case authorize_conversation_access(user_id, conversation_id) do
      {:ok, _conversation} ->
        result =
          %Message{}
          |> Message.changeset(%{
            conversation_id: conversation_id,
            sender_id: user_id,
            content: content
          })
          |> Repo.insert()

        case result do
          {:ok, message} = success ->
            broadcast_to_conversation(conversation_id, message)
            broadcast_new_message(conversation_id, message)
            success

          error ->
            error
        end

      {:error, :not_found} ->
        {:error, :not_authorized}
    end
  end

  defp authorize_conversation_access(user_id, conversation_id) do
    conversation =
      from(c in Conversation,
        join: m in Match,
        on: c.match_id == m.id,
        where: c.id == ^conversation_id,
        where: m.user_a_id == ^user_id or m.user_b_id == ^user_id,
        select: c
      )
      |> Repo.one()

    case conversation do
      nil -> {:error, :not_found}
      conv -> {:ok, conv}
    end
  end

  defp broadcast_to_conversation(conversation_id, message) do
    Phoenix.PubSub.broadcast(
      LittleGrape.PubSub,
      "conversation:#{conversation_id}",
      {:new_message, message}
    )
  end

  @doc """
  Marks all unread messages from other users as read in a conversation.

  Only marks messages sent by OTHER users as read (not the user's own messages).
  Broadcasts a :messages_read event to the conversation topic.

  ## Parameters

    * `user` - The user marking messages as read
    * `conversation_id` - The ID of the conversation

  ## Returns

    * `{:ok, count}` - Number of messages marked as read
    * `{:error, :not_authorized}` - User is not a participant in the conversation

  ## Examples

      iex> mark_as_read(user, conversation_id)
      {:ok, 3}

  """
  def mark_as_read(%User{id: user_id}, conversation_id) do
    case authorize_conversation_access(user_id, conversation_id) do
      {:ok, _conversation} ->
        read_at = DateTime.utc_now() |> DateTime.truncate(:second)

        {count, _} =
          from(m in Message,
            where: m.conversation_id == ^conversation_id,
            where: m.sender_id != ^user_id,
            where: is_nil(m.read_at)
          )
          |> Repo.update_all(set: [read_at: read_at])

        if count > 0 do
          broadcast_messages_read(conversation_id, user_id)
        end

        {:ok, count}

      {:error, :not_found} ->
        {:error, :not_authorized}
    end
  end

  defp broadcast_messages_read(conversation_id, reader_id) do
    Phoenix.PubSub.broadcast(
      LittleGrape.PubSub,
      "conversation:#{conversation_id}",
      {:messages_read, %{conversation_id: conversation_id, reader_id: reader_id}}
    )
  end

  @doc """
  Counts total unread messages across all conversations for a user.

  Returns the sum of all unread messages from other users in all matches
  where the user is a participant.

  ## Parameters

    * `user` - The user to count unread messages for

  ## Returns

    * Integer count of total unread messages

  ## Examples

      iex> total_unread_count(user)
      15

  """
  def total_unread_count(%User{id: user_id}) do
    from(m in Message,
      join: c in Conversation,
      on: m.conversation_id == c.id,
      join: match in Match,
      on: c.match_id == match.id,
      where: match.user_a_id == ^user_id or match.user_b_id == ^user_id,
      where: m.sender_id != ^user_id,
      where: is_nil(m.read_at),
      select: count(m.id)
    )
    |> Repo.one()
  end
end
