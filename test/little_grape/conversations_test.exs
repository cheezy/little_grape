defmodule LittleGrape.ConversationsTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  defp create_match do
    user1 = user_fixture()
    user2 = user_fixture()

    {user_a_id, user_b_id} =
      if user1.id < user2.id, do: {user1.id, user2.id}, else: {user2.id, user1.id}

    %{num_rows: 1} =
      Repo.query!(
        "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5) RETURNING id",
        [user_a_id, user_b_id, DateTime.utc_now(), DateTime.utc_now(), DateTime.utc_now()]
      )

    result = Repo.query!("SELECT id FROM matches WHERE user_a_id = $1 AND user_b_id = $2", [user_a_id, user_b_id])
    [[match_id]] = result.rows
    {match_id, user_a_id, user_b_id}
  end

  describe "conversations table migration" do
    test "creates table with correct columns" do
      {match_id, _user_a, _user_b} = create_match()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )

      result = Repo.query!("SELECT match_id FROM conversations WHERE match_id = $1", [match_id])
      assert result.num_rows == 1
    end

    test "unique index on match_id - one conversation per match" do
      {match_id, _user_a, _user_b} = create_match()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )

      assert_raise Postgrex.Error, ~r/conversations_match_id_index/, fn ->
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )
      end
    end

    test "foreign key constraint on match_id" do
      assert_raise Postgrex.Error, ~r/conversations_match_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [-1, DateTime.utc_now(), DateTime.utc_now()]
        )
      end
    end

    test "cascade deletes conversations when match is deleted" do
      {match_id, user_a, _user_b} = create_match()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )

      # Delete user_a which cascades to delete the match
      Repo.query!("DELETE FROM users WHERE id = $1", [user_a])

      result = Repo.query!("SELECT COUNT(*) FROM conversations")
      [[count]] = result.rows
      assert count == 0
    end
  end

  describe "messages table migration" do
    test "creates table with correct columns including nullable read_at" do
      {match_id, user_a, _user_b} = create_match()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )

      result = Repo.query!("SELECT id FROM conversations WHERE match_id = $1", [match_id])
      [[conversation_id]] = result.rows

      # Insert message with null read_at (unread)
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO messages (conversation_id, sender_id, content, read_at, inserted_at) VALUES ($1, $2, $3, $4, $5)",
          [conversation_id, user_a, "Hello!", nil, DateTime.utc_now()]
        )

      result =
        Repo.query!(
          "SELECT conversation_id, sender_id, content, read_at FROM messages WHERE conversation_id = $1",
          [conversation_id]
        )

      assert result.num_rows == 1
      [[fetched_conv_id, fetched_sender_id, fetched_content, fetched_read_at]] = result.rows
      assert fetched_conv_id == conversation_id
      assert fetched_sender_id == user_a
      assert fetched_content == "Hello!"
      assert is_nil(fetched_read_at)
    end

    test "read_at can be set when message is read" do
      {match_id, user_a, _user_b} = create_match()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )

      result = Repo.query!("SELECT id FROM conversations WHERE match_id = $1", [match_id])
      [[conversation_id]] = result.rows

      read_time = DateTime.utc_now()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO messages (conversation_id, sender_id, content, read_at, inserted_at) VALUES ($1, $2, $3, $4, $5)",
          [conversation_id, user_a, "Hello!", read_time, DateTime.utc_now()]
        )

      result =
        Repo.query!("SELECT read_at FROM messages WHERE conversation_id = $1", [conversation_id])

      [[fetched_read_at]] = result.rows
      refute is_nil(fetched_read_at)
    end

    test "content has max length constraint" do
      {match_id, user_a, _user_b} = create_match()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )

      result = Repo.query!("SELECT id FROM conversations WHERE match_id = $1", [match_id])
      [[conversation_id]] = result.rows

      # Try to insert a message that's too long (>2000 chars)
      too_long_content = String.duplicate("a", 2001)

      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          "INSERT INTO messages (conversation_id, sender_id, content, read_at, inserted_at) VALUES ($1, $2, $3, $4, $5)",
          [conversation_id, user_a, too_long_content, nil, DateTime.utc_now()]
        )
      end
    end

    test "index on (conversation_id, inserted_at) exists" do
      result =
        Repo.query!(
          "SELECT indexname FROM pg_indexes WHERE tablename = 'messages' AND indexname = 'messages_conversation_id_inserted_at_index'"
        )

      assert result.num_rows == 1
    end

    test "index on (conversation_id, sender_id, read_at) exists" do
      result =
        Repo.query!(
          "SELECT indexname FROM pg_indexes WHERE tablename = 'messages' AND indexname = 'messages_conversation_id_sender_id_read_at_index'"
        )

      assert result.num_rows == 1
    end

    test "foreign key constraint on conversation_id" do
      user = user_fixture()

      assert_raise Postgrex.Error, ~r/messages_conversation_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO messages (conversation_id, sender_id, content, read_at, inserted_at) VALUES ($1, $2, $3, $4, $5)",
          [-1, user.id, "Hello!", nil, DateTime.utc_now()]
        )
      end
    end

    test "foreign key constraint on sender_id" do
      {match_id, _user_a, _user_b} = create_match()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )

      result = Repo.query!("SELECT id FROM conversations WHERE match_id = $1", [match_id])
      [[conversation_id]] = result.rows

      assert_raise Postgrex.Error, ~r/messages_sender_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO messages (conversation_id, sender_id, content, read_at, inserted_at) VALUES ($1, $2, $3, $4, $5)",
          [conversation_id, -1, "Hello!", nil, DateTime.utc_now()]
        )
      end
    end

    test "cascade deletes messages when conversation is deleted" do
      {match_id, user_a, _user_b} = create_match()

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO conversations (match_id, inserted_at, updated_at) VALUES ($1, $2, $3)",
          [match_id, DateTime.utc_now(), DateTime.utc_now()]
        )

      result = Repo.query!("SELECT id FROM conversations WHERE match_id = $1", [match_id])
      [[conversation_id]] = result.rows

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO messages (conversation_id, sender_id, content, read_at, inserted_at) VALUES ($1, $2, $3, $4, $5)",
          [conversation_id, user_a, "Hello!", nil, DateTime.utc_now()]
        )

      # Delete the conversation
      Repo.query!("DELETE FROM conversations WHERE id = $1", [conversation_id])

      result = Repo.query!("SELECT COUNT(*) FROM messages")
      [[count]] = result.rows
      assert count == 0
    end
  end
end
