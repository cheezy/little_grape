defmodule LittleGrape.Messaging.MessageTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Messaging.Message
  alias LittleGrape.Repo

  defp create_conversation_with_users do
    user_a = user_fixture()
    user_b = user_fixture()
    {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, user_b.id)

    {:ok, match} =
      %Match{}
      |> Match.changeset(%{
        user_a_id: smaller_id,
        user_b_id: larger_id,
        matched_at: DateTime.utc_now()
      })
      |> Repo.insert()

    {:ok, conversation} =
      %Conversation{}
      |> Conversation.changeset(%{match_id: match.id})
      |> Repo.insert()

    # Return users in the order they were created, not the normalized order
    sender = if user_a.id == smaller_id, do: user_a, else: user_b
    receiver = if user_a.id == smaller_id, do: user_b, else: user_a

    {conversation, sender, receiver}
  end

  describe "schema" do
    test "has expected fields" do
      fields = Message.__schema__(:fields)

      assert :id in fields
      assert :conversation_id in fields
      assert :sender_id in fields
      assert :content in fields
      assert :read_at in fields
      assert :inserted_at in fields
    end

    test "does not have updated_at field" do
      fields = Message.__schema__(:fields)

      refute :updated_at in fields
    end

    test "has belongs_to conversation association" do
      associations = Message.__schema__(:associations)

      assert :conversation in associations
    end

    test "has belongs_to sender association" do
      associations = Message.__schema__(:associations)

      assert :sender in associations
    end
  end

  describe "max_content_length/0" do
    test "returns 2000" do
      assert Message.max_content_length() == 2000
    end
  end

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
    end

    test "valid changeset with read_at" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: "Hello!",
        read_at: DateTime.utc_now()
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
    end

    test "invalid changeset when missing conversation_id" do
      {_conversation, sender, _receiver} = create_conversation_with_users()

      attrs = %{
        sender_id: sender.id,
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).conversation_id
    end

    test "invalid changeset when missing sender_id" do
      {conversation, _sender, _receiver} = create_conversation_with_users()

      attrs = %{
        conversation_id: conversation.id,
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).sender_id
    end

    test "invalid changeset when missing content" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).content
    end

    test "invalid changeset when content is empty string" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: ""
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      # Empty string triggers both validate_required and validate_length
      assert errors_on(changeset).content != []
    end

    test "invalid changeset when content exceeds 2000 characters" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      long_content = String.duplicate("a", 2001)

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: long_content
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "should be at most 2000 character(s)" in errors_on(changeset).content
    end

    test "valid changeset when content is exactly 2000 characters" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      max_content = String.duplicate("a", 2000)

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: max_content
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
    end
  end

  describe "mark_read_changeset/2" do
    test "sets read_at to provided timestamp" do
      message = %Message{}
      read_time = DateTime.utc_now()

      changeset = Message.mark_read_changeset(message, read_time)

      assert changeset.changes.read_at == read_time
    end

    test "sets read_at to current time when not provided" do
      message = %Message{}

      changeset = Message.mark_read_changeset(message)

      assert changeset.changes.read_at != nil
    end
  end

  describe "database integration" do
    test "can insert a valid message" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: "Hello, this is a test message!"
      }

      assert {:ok, message} =
               %Message{}
               |> Message.changeset(attrs)
               |> Repo.insert()

      assert message.id
      assert message.conversation_id == conversation.id
      assert message.sender_id == sender.id
      assert message.content == "Hello, this is a test message!"
      assert message.read_at == nil
      assert message.inserted_at
    end

    test "can insert message with read_at" do
      {conversation, sender, _receiver} = create_conversation_with_users()
      read_time = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: "Already read message",
        read_at: read_time
      }

      assert {:ok, message} =
               %Message{}
               |> Message.changeset(attrs)
               |> Repo.insert()

      assert message.read_at == read_time
    end

    test "enforces foreign key constraint on conversation_id" do
      {_conversation, sender, _receiver} = create_conversation_with_users()
      non_existent_id = 999_999

      assert {:error, changeset} =
               %Message{}
               |> Message.changeset(%{
                 conversation_id: non_existent_id,
                 sender_id: sender.id,
                 content: "Test"
               })
               |> Repo.insert()

      assert "does not exist" in errors_on(changeset).conversation_id
    end

    test "enforces foreign key constraint on sender_id" do
      {conversation, _sender, _receiver} = create_conversation_with_users()
      non_existent_id = 999_999

      assert {:error, changeset} =
               %Message{}
               |> Message.changeset(%{
                 conversation_id: conversation.id,
                 sender_id: non_existent_id,
                 content: "Test"
               })
               |> Repo.insert()

      assert "does not exist" in errors_on(changeset).sender_id
    end

    test "can preload conversation association" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          conversation_id: conversation.id,
          sender_id: sender.id,
          content: "Test message"
        })
        |> Repo.insert()

      message = Repo.preload(message, :conversation)

      assert message.conversation.id == conversation.id
    end

    test "can preload sender association" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          conversation_id: conversation.id,
          sender_id: sender.id,
          content: "Test message"
        })
        |> Repo.insert()

      message = Repo.preload(message, :sender)

      assert message.sender.id == sender.id
    end

    test "message is deleted when conversation is deleted" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          conversation_id: conversation.id,
          sender_id: sender.id,
          content: "Test message"
        })
        |> Repo.insert()

      message_id = message.id

      # Delete the conversation
      Repo.delete!(conversation)

      # Message should be deleted too
      assert Repo.get(Message, message_id) == nil
    end

    test "message is deleted when sender is deleted" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          conversation_id: conversation.id,
          sender_id: sender.id,
          content: "Test message"
        })
        |> Repo.insert()

      message_id = message.id

      # Delete the sender
      Repo.delete!(sender)

      # Message should be deleted too
      assert Repo.get(Message, message_id) == nil
    end

    test "can update read_at on existing message" do
      {conversation, sender, _receiver} = create_conversation_with_users()

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          conversation_id: conversation.id,
          sender_id: sender.id,
          content: "Unread message"
        })
        |> Repo.insert()

      assert message.read_at == nil

      read_time = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, updated_message} =
        message
        |> Message.mark_read_changeset(read_time)
        |> Repo.update()

      assert updated_message.read_at == read_time
    end
  end
end
