defmodule LittleGrape.Messaging do
  @moduledoc """
  The Messaging context.
  """

  import Ecto.Query, warn: false

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
    %Message{}
    |> Message.changeset(%{
      conversation_id: conversation_id,
      sender_id: sender_id,
      content: content
    })
    |> Repo.insert()
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
end
