defmodule LittleGrape.MessagingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `LittleGrape.Messaging` context.
  """

  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Messaging.Message
  alias LittleGrape.Repo

  @doc """
  Inserts a message directly, bypassing `Messaging.send_message/3`
  authorization and block checks, and broadcasts `{:message_received, message}`
  to both match participants' `user:<id>` topics so LiveView tests receive
  real-time delivery. Returns `{:ok, message}` or `{:error, changeset}`.
  """
  def message_fixture(conversation_id, sender_id, content) do
    result =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation_id,
        sender_id: sender_id,
        content: content
      })
      |> Repo.insert()

    with {:ok, message} <- result do
      broadcast_to_participants(message)
      result
    end
  end

  defp broadcast_to_participants(message) do
    conversation =
      Conversation
      |> Repo.get(message.conversation_id)
      |> Repo.preload(:match)

    if conversation && conversation.match do
      for user_id <- [conversation.match.user_a_id, conversation.match.user_b_id] do
        Phoenix.PubSub.broadcast(
          LittleGrape.PubSub,
          "user:#{user_id}",
          {:message_received, message}
        )
      end
    end
  end
end
