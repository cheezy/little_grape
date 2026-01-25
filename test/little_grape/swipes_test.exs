defmodule LittleGrape.SwipesTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  describe "swipes table migration" do
    test "creates table with correct columns" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Insert a swipe record directly
      %{num_rows: 1} = Repo.query!(
        "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
        [user1.id, user2.id, "like", DateTime.utc_now()]
      )

      # Verify we can query it back
      result = Repo.query!("SELECT user_id, target_user_id, action FROM swipes WHERE user_id = $1", [user1.id])
      assert result.num_rows == 1
      [[user_id, target_user_id, action]] = result.rows
      assert user_id == user1.id
      assert target_user_id == user2.id
      assert action == "like"
    end

    test "unique index on (user_id, target_user_id) prevents duplicate swipes" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Insert first swipe
      %{num_rows: 1} = Repo.query!(
        "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
        [user1.id, user2.id, "like", DateTime.utc_now()]
      )

      # Attempt to insert duplicate swipe should fail
      assert_raise Postgrex.Error, ~r/swipes_user_id_target_user_id_index/, fn ->
        Repo.query!(
          "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
          [user1.id, user2.id, "pass", DateTime.utc_now()]
        )
      end
    end

    test "allows different user pairs" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      # User1 swipes on User2
      %{num_rows: 1} = Repo.query!(
        "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
        [user1.id, user2.id, "like", DateTime.utc_now()]
      )

      # User1 swipes on User3 (different target, should work)
      %{num_rows: 1} = Repo.query!(
        "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
        [user1.id, user3.id, "pass", DateTime.utc_now()]
      )

      # User2 swipes on User1 (reverse direction, should work)
      %{num_rows: 1} = Repo.query!(
        "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
        [user2.id, user1.id, "like", DateTime.utc_now()]
      )

      result = Repo.query!("SELECT COUNT(*) FROM swipes")
      [[count]] = result.rows
      assert count == 3
    end

    test "foreign key constraint on user_id" do
      user = user_fixture()

      # Attempt to insert with non-existent user_id should fail
      assert_raise Postgrex.Error, ~r/swipes_user_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
          [-1, user.id, "like", DateTime.utc_now()]
        )
      end
    end

    test "foreign key constraint on target_user_id" do
      user = user_fixture()

      # Attempt to insert with non-existent target_user_id should fail
      assert_raise Postgrex.Error, ~r/swipes_target_user_id_fkey/, fn ->
        Repo.query!(
          "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
          [user.id, -1, "like", DateTime.utc_now()]
        )
      end
    end

    test "index on (target_user_id, action) exists" do
      # Verify the index exists by checking the pg_indexes view
      result = Repo.query!(
        "SELECT indexname FROM pg_indexes WHERE tablename = 'swipes' AND indexname = 'swipes_target_user_id_action_index'"
      )
      assert result.num_rows == 1
    end

    test "cascade deletes swipes when user is deleted" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Insert swipe
      %{num_rows: 1} = Repo.query!(
        "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
        [user1.id, user2.id, "like", DateTime.utc_now()]
      )

      # Delete user1
      Repo.query!("DELETE FROM users WHERE id = $1", [user1.id])

      # Swipe should be deleted
      result = Repo.query!("SELECT COUNT(*) FROM swipes WHERE user_id = $1", [user1.id])
      [[count]] = result.rows
      assert count == 0
    end
  end
end
