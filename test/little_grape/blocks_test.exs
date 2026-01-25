defmodule LittleGrape.BlocksTest do
  use LittleGrape.DataCase, async: true

  alias LittleGrape.Repo

  describe "blocks table" do
    test "table exists with correct columns" do
      # Insert a test user first
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["blocker@test.com", "hashed"]
        )

      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["blocked@test.com", "hashed"]
        )

      # Get user IDs
      %{rows: [[blocker_id]]} =
        Repo.query!("SELECT id FROM users WHERE email = $1", ["blocker@test.com"])

      %{rows: [[blocked_id]]} =
        Repo.query!("SELECT id FROM users WHERE email = $1", ["blocked@test.com"])

      # Insert a block record
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO blocks (blocker_id, blocked_id, inserted_at) VALUES ($1, $2, NOW())",
          [blocker_id, blocked_id]
        )

      # Verify the record exists
      %{rows: [[_id, ^blocker_id, ^blocked_id, inserted_at]]} =
        Repo.query!("SELECT id, blocker_id, blocked_id, inserted_at FROM blocks LIMIT 1", [])

      assert inserted_at != nil
    end

    test "unique index prevents duplicate blocks" do
      # Insert test users
      %{rows: [[blocker_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["blocker2@test.com", "hashed"]
        )

      %{rows: [[blocked_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["blocked2@test.com", "hashed"]
        )

      # Insert first block
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO blocks (blocker_id, blocked_id, inserted_at) VALUES ($1, $2, NOW())",
          [blocker_id, blocked_id]
        )

      # Try to insert duplicate - should fail
      assert_raise Postgrex.Error, ~r/blocks_blocker_id_blocked_id_index/, fn ->
        Repo.query!(
          "INSERT INTO blocks (blocker_id, blocked_id, inserted_at) VALUES ($1, $2, NOW())",
          [blocker_id, blocked_id]
        )
      end
    end

    test "check constraint prevents user from blocking themselves" do
      # Insert a test user
      %{rows: [[user_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["selfblock@test.com", "hashed"]
        )

      # Try to insert self-block - should fail
      assert_raise Postgrex.Error, ~r/cannot_block_self/, fn ->
        Repo.query!(
          "INSERT INTO blocks (blocker_id, blocked_id, inserted_at) VALUES ($1, $2, NOW())",
          [user_id, user_id]
        )
      end
    end

    test "foreign key constraint on blocker_id" do
      # Insert a valid user for blocked_id
      %{rows: [[blocked_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["fk_blocked@test.com", "hashed"]
        )

      # Use a non-existent blocker_id - should be greater to avoid self-block constraint
      non_existent_blocker_id = blocked_id + 999_999

      # Try to insert with non-existent blocker_id - should fail
      assert_raise Postgrex.Error, ~r/blocks_blocker_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO blocks (blocker_id, blocked_id, inserted_at) VALUES ($1, $2, NOW())",
          [non_existent_blocker_id, blocked_id]
        )
      end
    end

    test "foreign key constraint on blocked_id" do
      # Insert a valid user for blocker_id
      %{rows: [[blocker_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["fk_blocker@test.com", "hashed"]
        )

      # Use a non-existent blocked_id - should be greater to avoid self-block constraint
      non_existent_blocked_id = blocker_id + 999_999

      # Try to insert with non-existent blocked_id - should fail
      assert_raise Postgrex.Error, ~r/blocks_blocked_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO blocks (blocker_id, blocked_id, inserted_at) VALUES ($1, $2, NOW())",
          [blocker_id, non_existent_blocked_id]
        )
      end
    end

    test "cascade delete when blocker user is deleted" do
      # Insert test users
      %{rows: [[blocker_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["cascade_blocker@test.com", "hashed"]
        )

      %{rows: [[blocked_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["cascade_blocked@test.com", "hashed"]
        )

      # Insert block
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO blocks (blocker_id, blocked_id, inserted_at) VALUES ($1, $2, NOW())",
          [blocker_id, blocked_id]
        )

      # Verify block exists
      %{rows: [[1]]} =
        Repo.query!("SELECT COUNT(*) FROM blocks WHERE blocker_id = $1", [blocker_id])

      # Delete blocker user
      %{num_rows: 1} = Repo.query!("DELETE FROM users WHERE id = $1", [blocker_id])

      # Verify block was cascade deleted
      %{rows: [[0]]} =
        Repo.query!("SELECT COUNT(*) FROM blocks WHERE blocker_id = $1", [blocker_id])
    end

    test "cascade delete when blocked user is deleted" do
      # Insert test users
      %{rows: [[blocker_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["cascade_blocker2@test.com", "hashed"]
        )

      %{rows: [[blocked_id]]} =
        Repo.query!(
          "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
          ["cascade_blocked2@test.com", "hashed"]
        )

      # Insert block
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO blocks (blocker_id, blocked_id, inserted_at) VALUES ($1, $2, NOW())",
          [blocker_id, blocked_id]
        )

      # Verify block exists
      %{rows: [[1]]} =
        Repo.query!("SELECT COUNT(*) FROM blocks WHERE blocked_id = $1", [blocked_id])

      # Delete blocked user
      %{num_rows: 1} = Repo.query!("DELETE FROM users WHERE id = $1", [blocked_id])

      # Verify block was cascade deleted
      %{rows: [[0]]} =
        Repo.query!("SELECT COUNT(*) FROM blocks WHERE blocked_id = $1", [blocked_id])
    end
  end
end
