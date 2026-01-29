defmodule LittleGrape.MessagingTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Matches
  alias LittleGrape.Messaging
  alias LittleGrape.Messaging.Message
  alias LittleGrape.Repo

  describe "create_message/3" do
    test "creates a message with valid attributes" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      assert {:ok, message} = Messaging.create_message(conversation.id, user1.id, "Hello!")
      assert message.content == "Hello!"
      assert message.conversation_id == conversation.id
      assert message.sender_id == user1.id
      assert is_nil(message.read_at)
    end

    test "fails with empty content" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      assert {:error, changeset} = Messaging.create_message(conversation.id, user1.id, "")
      assert "can't be blank" in errors_on(changeset).content
    end

    test "fails with content exceeding max length" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      long_content = String.duplicate("a", Message.max_content_length() + 1)

      assert {:error, changeset} =
               Messaging.create_message(conversation.id, user1.id, long_content)

      assert "should be at most #{Message.max_content_length()} character(s)" in errors_on(
               changeset
             ).content
    end
  end

  describe "unread_count/2" do
    test "returns 0 when no messages" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      assert Messaging.unread_count(conversation.id, user1.id) == 0
    end

    test "returns count of unread messages from other user" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # user2 sends messages to user1 (unread for user1)
      {:ok, _} = Messaging.create_message(conversation.id, user2.id, "Message 1")
      {:ok, _} = Messaging.create_message(conversation.id, user2.id, "Message 2")
      {:ok, _} = Messaging.create_message(conversation.id, user2.id, "Message 3")

      assert Messaging.unread_count(conversation.id, user1.id) == 3
    end

    test "does not count messages sent by self" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # user1 sends messages (should not count as unread for user1)
      {:ok, _} = Messaging.create_message(conversation.id, user1.id, "My message 1")
      {:ok, _} = Messaging.create_message(conversation.id, user1.id, "My message 2")

      assert Messaging.unread_count(conversation.id, user1.id) == 0
    end

    test "does not count read messages" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # user2 sends messages
      {:ok, msg1} = Messaging.create_message(conversation.id, user2.id, "Message 1")
      {:ok, _msg2} = Messaging.create_message(conversation.id, user2.id, "Message 2")

      # Mark first message as read (truncate to second for utc_datetime field)
      read_at = DateTime.utc_now() |> DateTime.truncate(:second)

      msg1
      |> Message.mark_read_changeset(read_at)
      |> Repo.update!()

      assert Messaging.unread_count(conversation.id, user1.id) == 1
    end

    test "counts correctly with mixed sent and received messages" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # Mixed conversation
      {:ok, _} = Messaging.create_message(conversation.id, user1.id, "From user1")
      {:ok, _} = Messaging.create_message(conversation.id, user2.id, "From user2 - 1")
      {:ok, _} = Messaging.create_message(conversation.id, user1.id, "From user1 again")
      {:ok, _} = Messaging.create_message(conversation.id, user2.id, "From user2 - 2")

      # user1 should see 2 unread (messages from user2)
      assert Messaging.unread_count(conversation.id, user1.id) == 2
      # user2 should see 2 unread (messages from user1)
      assert Messaging.unread_count(conversation.id, user2.id) == 2
    end
  end

  describe "unread_counts_for_conversations/2" do
    test "returns empty map for empty list" do
      user = user_fixture()
      assert Messaging.unread_counts_for_conversations([], user.id) == %{}
    end

    test "returns counts for multiple conversations" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, %{conversation: conv1}} = Matches.create_match(user1.id, user2.id)
      {:ok, %{conversation: conv2}} = Matches.create_match(user1.id, user3.id)

      # user2 sends 2 messages to conv1
      {:ok, _} = Messaging.create_message(conv1.id, user2.id, "From user2 - 1")
      {:ok, _} = Messaging.create_message(conv1.id, user2.id, "From user2 - 2")

      # user3 sends 3 messages to conv2
      {:ok, _} = Messaging.create_message(conv2.id, user3.id, "From user3 - 1")
      {:ok, _} = Messaging.create_message(conv2.id, user3.id, "From user3 - 2")
      {:ok, _} = Messaging.create_message(conv2.id, user3.id, "From user3 - 3")

      counts = Messaging.unread_counts_for_conversations([conv1.id, conv2.id], user1.id)

      assert counts[conv1.id] == 2
      assert counts[conv2.id] == 3
    end

    test "returns only non-zero counts in the map" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, %{conversation: conv1}} = Matches.create_match(user1.id, user2.id)
      {:ok, %{conversation: conv2}} = Matches.create_match(user1.id, user3.id)

      # Only send messages in conv1
      {:ok, _} = Messaging.create_message(conv1.id, user2.id, "Message")

      counts = Messaging.unread_counts_for_conversations([conv1.id, conv2.id], user1.id)

      assert counts[conv1.id] == 1
      # conv2 has no unread messages, so it won't be in the map
      refute Map.has_key?(counts, conv2.id)
    end
  end
end
