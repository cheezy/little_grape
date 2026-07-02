defmodule LittleGrape.ConversationsTest do
  @moduledoc """
  Schema-integration tests that span the matches/conversations/messages
  tables: deep cascade behavior, index existence, and column limits.

  Application-level behavior lives in `LittleGrape.MessagingTest`; per-schema
  changeset and constraint coverage lives in `LittleGrape.Messaging.ConversationTest`
  and `LittleGrape.Messaging.MessageTest`.
  """
  use LittleGrape.DataCase, async: true

  import Ecto.Query
  import LittleGrape.AccountsFixtures
  import LittleGrape.MessagingFixtures

  alias LittleGrape.Matches
  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Messaging.Message
  alias LittleGrape.Repo

  describe "deep cascade" do
    test "deleting a user cascades through match, conversation, and messages" do
      user_a = user_fixture()
      user_b = user_fixture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user_a.id, user_b.id)

      {:ok, message} = message_fixture(conversation.id, user_a.id, "Hello!")

      Repo.delete!(user_a)

      assert Repo.get(Match, match.id) == nil
      assert Repo.get(Conversation, conversation.id) == nil
      assert Repo.get(Message, message.id) == nil
    end
  end

  describe "message indexes" do
    defp index_exists?(index_name) do
      query =
        from(i in "pg_indexes",
          where: i.tablename == "messages" and i.indexname == ^index_name
        )

      Repo.exists?(query)
    end

    test "index on (conversation_id, inserted_at) exists" do
      assert index_exists?("messages_conversation_id_inserted_at_index")
    end

    test "index on (conversation_id, sender_id, read_at) exists" do
      assert index_exists?("messages_conversation_id_sender_id_read_at_index")
    end
  end

  describe "database column limits" do
    test "varchar(2000) rejects over-limit content even when validation is bypassed" do
      {conversation, sender, _receiver} = conversation_with_users_fixture()

      assert_raise Postgrex.Error, fn ->
        %Message{}
        |> Ecto.Changeset.change(
          conversation_id: conversation.id,
          sender_id: sender.id,
          content: String.duplicate("a", 2001)
        )
        |> Repo.insert()
      end
    end
  end
end
