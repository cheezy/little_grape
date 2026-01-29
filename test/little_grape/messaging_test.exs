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

  describe "get_conversation/2" do
    test "returns conversation for match participant" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user1.id, user2.id)

      assert {:ok, fetched_conv} = Messaging.get_conversation(user1, match.id)
      assert fetched_conv.id == conversation.id
    end

    test "returns conversation for both participants" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user1.id, user2.id)

      # user1 can access
      assert {:ok, conv1} = Messaging.get_conversation(user1, match.id)
      assert conv1.id == conversation.id

      # user2 can also access
      assert {:ok, conv2} = Messaging.get_conversation(user2, match.id)
      assert conv2.id == conversation.id
    end

    test "returns error for non-participant" do
      user1 = user_fixture()
      user2 = user_fixture()
      non_participant = user_fixture()
      {:ok, %{match: match}} = Matches.create_match(user1.id, user2.id)

      assert {:error, :not_found} = Messaging.get_conversation(non_participant, match.id)
    end

    test "returns error for non-existent match" do
      user = user_fixture()
      assert {:error, :not_found} = Messaging.get_conversation(user, 999_999)
    end
  end

  describe "list_messages/2" do
    test "returns empty list for conversation with no messages" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      assert Messaging.list_messages(conversation) == []
    end

    test "returns messages ordered by inserted_at ascending" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      {:ok, msg1} = Messaging.create_message(conversation.id, user1.id, "First")
      {:ok, msg2} = Messaging.create_message(conversation.id, user2.id, "Second")
      {:ok, msg3} = Messaging.create_message(conversation.id, user1.id, "Third")

      messages = Messaging.list_messages(conversation)

      assert length(messages) == 3
      assert Enum.at(messages, 0).id == msg1.id
      assert Enum.at(messages, 1).id == msg2.id
      assert Enum.at(messages, 2).id == msg3.id
    end

    test "respects limit option" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # Create 5 messages
      for i <- 1..5 do
        {:ok, _} = Messaging.create_message(conversation.id, user1.id, "Message #{i}")
      end

      messages = Messaging.list_messages(conversation, limit: 3)

      assert length(messages) == 3
      # Should get the first 3 messages (oldest first)
      assert Enum.at(messages, 0).content == "Message 1"
      assert Enum.at(messages, 1).content == "Message 2"
      assert Enum.at(messages, 2).content == "Message 3"
    end

    test "respects offset option" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # Create 5 messages
      for i <- 1..5 do
        {:ok, _} = Messaging.create_message(conversation.id, user1.id, "Message #{i}")
      end

      messages = Messaging.list_messages(conversation, offset: 2)

      assert length(messages) == 3
      # Should skip first 2, get messages 3-5
      assert Enum.at(messages, 0).content == "Message 3"
      assert Enum.at(messages, 1).content == "Message 4"
      assert Enum.at(messages, 2).content == "Message 5"
    end

    test "respects both limit and offset options" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # Create 10 messages
      for i <- 1..10 do
        {:ok, _} = Messaging.create_message(conversation.id, user1.id, "Message #{i}")
      end

      messages = Messaging.list_messages(conversation, limit: 3, offset: 4)

      assert length(messages) == 3
      # Should skip first 4, get messages 5-7
      assert Enum.at(messages, 0).content == "Message 5"
      assert Enum.at(messages, 1).content == "Message 6"
      assert Enum.at(messages, 2).content == "Message 7"
    end

    test "accepts conversation id directly" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      {:ok, _} = Messaging.create_message(conversation.id, user1.id, "Test message")

      messages = Messaging.list_messages(conversation.id)

      assert length(messages) == 1
      assert Enum.at(messages, 0).content == "Test message"
    end

    test "uses default limit of 50" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # Create 60 messages
      for i <- 1..60 do
        {:ok, _} = Messaging.create_message(conversation.id, user1.id, "Message #{i}")
      end

      messages = Messaging.list_messages(conversation)

      assert length(messages) == 50
    end
  end

  describe "send_message/3" do
    test "creates message successfully for authorized user" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      assert {:ok, message} = Messaging.send_message(user1, conversation.id, "Hello!")
      assert message.content == "Hello!"
      assert message.sender_id == user1.id
      assert message.conversation_id == conversation.id
    end

    test "both match participants can send messages" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      assert {:ok, msg1} = Messaging.send_message(user1, conversation.id, "From user1")
      assert {:ok, msg2} = Messaging.send_message(user2, conversation.id, "From user2")

      assert msg1.sender_id == user1.id
      assert msg2.sender_id == user2.id
    end

    test "returns error for non-participant" do
      user1 = user_fixture()
      user2 = user_fixture()
      non_participant = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      assert {:error, :not_authorized} =
               Messaging.send_message(non_participant, conversation.id, "Hello!")
    end

    test "returns error for non-existent conversation" do
      user = user_fixture()

      assert {:error, :not_authorized} = Messaging.send_message(user, 999_999, "Hello!")
    end

    test "validates content is not empty" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      assert {:error, changeset} = Messaging.send_message(user1, conversation.id, "")
      assert "can't be blank" in errors_on(changeset).content
    end

    test "validates content does not exceed 2000 chars" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      long_content = String.duplicate("a", 2001)

      assert {:error, changeset} = Messaging.send_message(user1, conversation.id, long_content)
      assert "should be at most 2000 character(s)" in errors_on(changeset).content
    end

    test "broadcasts to conversation topic" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # Subscribe to the conversation topic
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "conversation:#{conversation.id}")

      {:ok, message} = Messaging.send_message(user1, conversation.id, "Broadcast test")

      # Should receive the broadcast
      assert_receive {:new_message, received_message}
      assert received_message.id == message.id
    end

    test "broadcasts to user topics" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # Subscribe to user topics
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user1.id}")
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user2.id}")

      {:ok, message} = Messaging.send_message(user1, conversation.id, "User broadcast test")

      # Should receive broadcasts on both user topics
      assert_receive {:new_message, msg1}
      assert_receive {:new_message, msg2}
      assert msg1.id == message.id
      assert msg2.id == message.id
    end

    test "does not broadcast on validation error" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, %{conversation: conversation}} = Matches.create_match(user1.id, user2.id)

      # Subscribe to the conversation topic
      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "conversation:#{conversation.id}")

      {:error, _changeset} = Messaging.send_message(user1, conversation.id, "")

      # Should NOT receive any broadcast
      refute_receive {:new_message, _}
    end
  end
end
