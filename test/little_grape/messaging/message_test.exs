defmodule LittleGrape.Messaging.MessageTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.MessagingFixtures

  alias LittleGrape.Messaging.Message
  alias LittleGrape.Repo

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
      {conversation, sender, _receiver} = conversation_with_users_fixture()

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
    end

    test "valid changeset with read_at" do
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
      {_conversation, sender, _receiver} = conversation_with_users_fixture()

      attrs = %{
        sender_id: sender.id,
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).conversation_id
    end

    test "invalid changeset when missing sender_id" do
      {conversation, _sender, _receiver} = conversation_with_users_fixture()

      attrs = %{
        conversation_id: conversation.id,
        content: "Hello!"
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).sender_id
    end

    test "invalid changeset when missing content" do
      {conversation, sender, _receiver} = conversation_with_users_fixture()

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).content
    end

    test "invalid changeset when content is empty string" do
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
      {conversation, sender, _receiver} = conversation_with_users_fixture()

      max_content = String.duplicate("a", 2000)

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: max_content
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
    end

    test "counts codepoints so multi-codepoint graphemes cannot exceed the column limit" do
      {conversation, sender, _receiver} = conversation_with_users_fixture()

      # "👩‍🚀" is one grapheme but three codepoints: 1998 + 3 = 2001 codepoints,
      # which the varchar(2000) column would reject even though the grapheme
      # count (1999) is under the limit.
      content = String.duplicate("a", 1998) <> "👩‍🚀"
      assert String.length(content) == 1999

      attrs = %{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: content
      }

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert "should be at most 2000 character(s)" in errors_on(changeset).content
    end
  end

  describe "database integration" do
    test "can insert a valid message" do
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
      {conversation, sender, _receiver} = conversation_with_users_fixture()
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
      {_conversation, sender, _receiver} = conversation_with_users_fixture()
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
      {conversation, _sender, _receiver} = conversation_with_users_fixture()
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
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
      {conversation, sender, _receiver} = conversation_with_users_fixture()

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
        |> Ecto.Changeset.change(read_at: read_time)
        |> Repo.update()

      assert updated_message.read_at == read_time
    end
  end
end
