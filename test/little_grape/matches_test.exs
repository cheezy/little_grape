defmodule LittleGrape.MatchesTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  describe "matches table migration" do
    test "creates table with correct columns" do
      user1 = user_fixture()
      user2 = user_fixture()
      matched_at = DateTime.utc_now()

      # Ensure user_a_id < user_b_id
      {user_a_id, user_b_id} =
        if user1.id < user2.id, do: {user1.id, user2.id}, else: {user2.id, user1.id}

      # Insert a match record directly
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [user_a_id, user_b_id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )

      # Verify we can query it back
      result =
        Repo.query!("SELECT user_a_id, user_b_id, matched_at FROM matches WHERE user_a_id = $1", [
          user_a_id
        ])

      assert result.num_rows == 1
      [[fetched_user_a_id, fetched_user_b_id, _fetched_matched_at]] = result.rows
      assert fetched_user_a_id == user_a_id
      assert fetched_user_b_id == user_b_id
    end

    test "unique constraint on (user_a_id, user_b_id) prevents duplicate matches" do
      user1 = user_fixture()
      user2 = user_fixture()
      matched_at = DateTime.utc_now()

      {user_a_id, user_b_id} =
        if user1.id < user2.id, do: {user1.id, user2.id}, else: {user2.id, user1.id}

      # Insert first match
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [user_a_id, user_b_id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )

      # Attempt to insert duplicate match should fail
      assert_raise Postgrex.Error, ~r/matches_user_a_id_user_b_id_index/, fn ->
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [user_a_id, user_b_id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )
      end
    end

    test "check constraint enforces user_a_id < user_b_id" do
      user1 = user_fixture()
      user2 = user_fixture()
      matched_at = DateTime.utc_now()

      # Ensure we're trying to insert with user_a_id > user_b_id
      {wrong_a, wrong_b} =
        if user1.id > user2.id, do: {user1.id, user2.id}, else: {user2.id, user1.id}

      # This should fail because user_a_id > user_b_id
      assert_raise Postgrex.Error, ~r/user_a_less_than_user_b/, fn ->
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [wrong_a, wrong_b, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )
      end
    end

    test "foreign key constraint on user_a_id" do
      user = user_fixture()
      matched_at = DateTime.utc_now()

      # Attempt to insert with non-existent user_a_id should fail
      assert_raise Postgrex.Error, ~r/matches_user_a_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [-1, user.id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )
      end
    end

    test "foreign key constraint on user_b_id" do
      user = user_fixture()
      matched_at = DateTime.utc_now()

      # Use a very large non-existent ID that's greater than user.id to pass the check constraint
      non_existent_id = user.id + 999_999

      # Attempt to insert with non-existent user_b_id should fail
      assert_raise Postgrex.Error, ~r/matches_user_b_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [user.id, non_existent_id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )
      end
    end

    test "allows multiple different matches" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()
      matched_at = DateTime.utc_now()

      # Sort users by ID for proper ordering
      users = Enum.sort_by([user1, user2, user3], & &1.id)
      [u1, u2, u3] = users

      # Match between u1 and u2
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [u1.id, u2.id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )

      # Match between u1 and u3
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [u1.id, u3.id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )

      # Match between u2 and u3
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [u2.id, u3.id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )

      result = Repo.query!("SELECT COUNT(*) FROM matches")
      [[count]] = result.rows
      assert count == 3
    end

    test "cascade deletes matches when user is deleted" do
      user1 = user_fixture()
      user2 = user_fixture()
      matched_at = DateTime.utc_now()

      {user_a_id, user_b_id} =
        if user1.id < user2.id, do: {user1.id, user2.id}, else: {user2.id, user1.id}

      # Insert match
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO matches (user_a_id, user_b_id, matched_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5)",
          [user_a_id, user_b_id, matched_at, DateTime.utc_now(), DateTime.utc_now()]
        )

      # Delete user_a
      Repo.query!("DELETE FROM users WHERE id = $1", [user_a_id])

      # Match should be deleted
      result = Repo.query!("SELECT COUNT(*) FROM matches")
      [[count]] = result.rows
      assert count == 0
    end
  end
end
