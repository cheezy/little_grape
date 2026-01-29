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
end
