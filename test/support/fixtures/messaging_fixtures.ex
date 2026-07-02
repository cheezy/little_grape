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

  @doc "Inserts a conversation for the given match id."
  def conversation_fixture(match_id) do
    {:ok, conversation} =
      %Conversation{}
      |> Conversation.changeset(%{match_id: match_id})
      |> Repo.insert()

    conversation
  end

  @doc """
  Creates two users, a match, and a conversation. Returns
  `{conversation, sender, receiver}` where `sender` is the user whose id equals
  the match's normalized `user_a_id`.
  """
  def conversation_with_users_fixture do
    user_a = LittleGrape.AccountsFixtures.user_fixture()
    user_b = LittleGrape.AccountsFixtures.user_fixture()
    match = LittleGrape.MatchesFixtures.match_fixture(user_a, user_b)
    conversation = conversation_fixture(match.id)

    sender = if user_a.id == match.user_a_id, do: user_a, else: user_b
    receiver = if user_a.id == match.user_a_id, do: user_b, else: user_a

    {conversation, sender, receiver}
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
