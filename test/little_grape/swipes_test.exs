defmodule LittleGrape.SwipesTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Matches
  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Swipes
  alias LittleGrape.Swipes.Swipe

  describe "swipe/3" do
    test "returns {:ok, :no_match} on a like without reciprocity" do
      user = user_fixture()
      target = user_fixture()

      assert {:ok, :no_match} = Swipes.swipe(user, target.id, "like")
      assert Swipes.has_swiped?(user.id, target.id)
      assert Repo.aggregate(Match, :count) == 0
    end

    test "returns {:ok, {:match, match}} on a mutual like and creates the conversation" do
      user = user_fixture()
      target = user_fixture()

      assert {:ok, _swipe} = Swipes.create_swipe(target, user.id, "like")
      assert {:ok, {:match, %Match{} = match}} = Swipes.swipe(user, target.id, "like")

      assert match.user_a_id < match.user_b_id
      assert Enum.sort([match.user_a_id, match.user_b_id]) == Enum.sort([user.id, target.id])
      assert Repo.get_by(Conversation, match_id: match.id)
    end

    test "a pass never creates a match even with a reciprocal like" do
      user = user_fixture()
      target = user_fixture()

      assert {:ok, _swipe} = Swipes.create_swipe(target, user.id, "like")
      assert {:ok, :no_match} = Swipes.swipe(user, target.id, "pass")
      assert Repo.aggregate(Match, :count) == 0
    end

    test "returns {:error, changeset} for an invalid action" do
      user = user_fixture()
      target = user_fixture()

      assert {:error, changeset} = Swipes.swipe(user, target.id, "invalid")
      assert "must be 'like' or 'pass'" in errors_on(changeset).action
      refute Swipes.has_swiped?(user.id, target.id)
    end

    test "returns {:error, changeset} when swiping an already-swiped target" do
      user = user_fixture()
      target = user_fixture()

      assert {:ok, _swipe} = Swipes.create_swipe(user, target.id, "like")
      assert {:error, changeset} = Swipes.swipe(user, target.id, "like")
      assert "has already been taken" in errors_on(changeset).user_id
      assert Repo.aggregate(Match, :count) == 0
    end

    test "regression: resolves to the existing match when the match row already exists" do
      user = user_fixture()
      target = user_fixture()

      # The other user's like plus an already-committed match simulates losing
      # the race: the concurrent transaction inserted the match first.
      assert {:ok, _swipe} = Swipes.create_swipe(target, user.id, "like")
      assert {:ok, %{match: existing}} = Matches.create_match(user.id, target.id)

      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user.id}")

      assert {:ok, {:match, match}} = Swipes.swipe(user, target.id, "like")
      assert match.id == existing.id

      # The swipe row survived the unique-index collision (no rollback)
      assert Swipes.has_swiped?(user.id, target.id)
      assert Repo.aggregate(Match, :count) == 1

      # Only the transaction that inserted the match broadcasts
      refute_receive {:new_match, _match}, 100
    end

    test "broadcasts :new_match exactly once on a mutual like" do
      user = user_fixture()
      target = user_fixture()

      Phoenix.PubSub.subscribe(LittleGrape.PubSub, "user:#{user.id}")

      assert {:ok, _swipe} = Swipes.create_swipe(target, user.id, "like")
      assert {:ok, {:match, match}} = Swipes.swipe(user, target.id, "like")

      assert_receive {:new_match, %Match{id: match_id}}
      assert match_id == match.id
      refute_receive {:new_match, _match}, 100
    end
  end

  describe "create_swipe/3" do
    test "creates a swipe with valid data" do
      user = user_fixture()
      target = user_fixture()

      assert {:ok, %Swipe{} = swipe} = Swipes.create_swipe(user, target.id, "like")
      assert swipe.user_id == user.id
      assert swipe.target_user_id == target.id
      assert swipe.action == "like"
    end

    test "creates a pass swipe" do
      user = user_fixture()
      target = user_fixture()

      assert {:ok, %Swipe{} = swipe} = Swipes.create_swipe(user, target.id, "pass")
      assert swipe.action == "pass"
    end

    test "returns error for invalid action" do
      user = user_fixture()
      target = user_fixture()

      assert {:error, changeset} = Swipes.create_swipe(user, target.id, "invalid")
      assert "must be 'like' or 'pass'" in errors_on(changeset).action
    end

    test "returns error for duplicate swipe" do
      user = user_fixture()
      target = user_fixture()

      assert {:ok, _swipe} = Swipes.create_swipe(user, target.id, "like")
      assert {:error, changeset} = Swipes.create_swipe(user, target.id, "pass")
      assert "has already been taken" in errors_on(changeset).user_id
    end

    test "returns error when target user does not exist" do
      user = user_fixture()
      non_existent_id = 999_999

      assert {:error, changeset} = Swipes.create_swipe(user, non_existent_id, "like")
      assert "does not exist" in errors_on(changeset).target_user_id
    end

    test "allows same target to be swiped by different users" do
      user1 = user_fixture()
      user2 = user_fixture()
      target = user_fixture()

      assert {:ok, _swipe1} = Swipes.create_swipe(user1, target.id, "like")
      assert {:ok, _swipe2} = Swipes.create_swipe(user2, target.id, "like")
    end

    test "allows user to swipe on multiple targets" do
      user = user_fixture()
      target1 = user_fixture()
      target2 = user_fixture()

      assert {:ok, _swipe1} = Swipes.create_swipe(user, target1.id, "like")
      assert {:ok, _swipe2} = Swipes.create_swipe(user, target2.id, "pass")
    end
  end

  describe "get_swipe/2" do
    test "returns swipe when it exists" do
      user = user_fixture()
      target = user_fixture()

      {:ok, created_swipe} = Swipes.create_swipe(user, target.id, "like")

      fetched_swipe = Swipes.get_swipe(user.id, target.id)
      assert fetched_swipe.id == created_swipe.id
    end

    test "returns nil when swipe does not exist" do
      user = user_fixture()
      target = user_fixture()

      assert Swipes.get_swipe(user.id, target.id) == nil
    end
  end

  describe "has_swiped?/2" do
    test "returns true when user has swiped on target" do
      user = user_fixture()
      target = user_fixture()

      {:ok, _swipe} = Swipes.create_swipe(user, target.id, "like")

      assert Swipes.has_swiped?(user.id, target.id) == true
    end

    test "returns false when user has not swiped on target" do
      user = user_fixture()
      target = user_fixture()

      assert Swipes.has_swiped?(user.id, target.id) == false
    end

    test "returns false for reverse direction" do
      user = user_fixture()
      target = user_fixture()

      {:ok, _swipe} = Swipes.create_swipe(user, target.id, "like")

      # User swiped on target, but target has not swiped on user
      assert Swipes.has_swiped?(target.id, user.id) == false
    end
  end

  describe "check_for_match/2" do
    test "returns true when target has liked user back" do
      user = user_fixture()
      target = user_fixture()

      # User likes target
      {:ok, _swipe1} = Swipes.create_swipe(user, target.id, "like")
      # Target likes user back
      {:ok, _swipe2} = Swipes.create_swipe(target, user.id, "like")

      # Check from user's perspective - target has liked them back
      assert Swipes.check_for_match(user.id, target.id) == true
    end

    test "returns false when no reciprocal like exists" do
      user = user_fixture()
      target = user_fixture()

      # Only user likes target
      {:ok, _swipe} = Swipes.create_swipe(user, target.id, "like")

      # Target has not liked user back
      assert Swipes.check_for_match(user.id, target.id) == false
    end

    test "returns false when target passed instead of liked" do
      user = user_fixture()
      target = user_fixture()

      # User likes target
      {:ok, _swipe1} = Swipes.create_swipe(user, target.id, "like")
      # Target passes on user (not a like)
      {:ok, _swipe2} = Swipes.create_swipe(target, user.id, "pass")

      # Pass doesn't count as a match
      assert Swipes.check_for_match(user.id, target.id) == false
    end

    test "returns false when no swipes exist" do
      user = user_fixture()
      target = user_fixture()

      # No swipes at all
      assert Swipes.check_for_match(user.id, target.id) == false
    end

    test "is directional - checks if target liked user" do
      user = user_fixture()
      target = user_fixture()

      # Target likes user
      {:ok, _swipe} = Swipes.create_swipe(target, user.id, "like")

      # From user's perspective, target has liked them
      assert Swipes.check_for_match(user.id, target.id) == true
      # From target's perspective, user has NOT liked them
      assert Swipes.check_for_match(target.id, user.id) == false
    end
  end

  describe "list_passed_target_ids/1" do
    test "returns target ids of pass swipes, most recent first" do
      user = user_fixture()
      first = user_fixture()
      second = user_fixture()
      liked = user_fixture()

      {:ok, _} = Swipes.create_swipe(user, first.id, "pass")
      {:ok, _} = Swipes.create_swipe(user, liked.id, "like")
      {:ok, _} = Swipes.create_swipe(user, second.id, "pass")

      assert Swipes.list_passed_target_ids(user) == [second.id, first.id]
    end

    test "returns empty list when user has no pass swipes" do
      user = user_fixture()
      target = user_fixture()
      {:ok, _} = Swipes.create_swipe(user, target.id, "like")

      assert Swipes.list_passed_target_ids(user) == []
    end

    test "scopes to the given user" do
      user = user_fixture()
      other_user = user_fixture()
      target = user_fixture()

      {:ok, _} = Swipes.create_swipe(other_user, target.id, "pass")

      assert Swipes.list_passed_target_ids(user) == []
    end
  end

  describe "delete_pass/2" do
    test "deletes a pass swipe and returns it" do
      user = user_fixture()
      target = user_fixture()
      {:ok, swipe} = Swipes.create_swipe(user, target.id, "pass")

      assert {:ok, deleted} = Swipes.delete_pass(user, target.id)
      assert deleted.id == swipe.id
      refute Swipes.has_swiped?(user.id, target.id)
    end

    test "refuses to delete a like swipe" do
      user = user_fixture()
      target = user_fixture()
      {:ok, _} = Swipes.create_swipe(user, target.id, "like")

      assert {:error, :not_found} = Swipes.delete_pass(user, target.id)
      assert Swipes.has_swiped?(user.id, target.id)
    end

    test "returns :not_found when no swipe exists" do
      user = user_fixture()
      target = user_fixture()

      assert {:error, :not_found} = Swipes.delete_pass(user, target.id)
    end
  end

  describe "swipes table migration" do
    test "creates table with correct columns" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Insert a swipe record directly
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
          [user1.id, user2.id, "like", DateTime.utc_now()]
        )

      # Verify we can query it back
      result =
        Repo.query!("SELECT user_id, target_user_id, action FROM swipes WHERE user_id = $1", [
          user1.id
        ])

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
      %{num_rows: 1} =
        Repo.query!(
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
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
          [user1.id, user2.id, "like", DateTime.utc_now()]
        )

      # User1 swipes on User3 (different target, should work)
      %{num_rows: 1} =
        Repo.query!(
          "INSERT INTO swipes (user_id, target_user_id, action, inserted_at) VALUES ($1, $2, $3, $4)",
          [user1.id, user3.id, "pass", DateTime.utc_now()]
        )

      # User2 swipes on User1 (reverse direction, should work)
      %{num_rows: 1} =
        Repo.query!(
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
      result =
        Repo.query!(
          "SELECT indexname FROM pg_indexes WHERE tablename = 'swipes' AND indexname = 'swipes_target_user_id_action_index'"
        )

      assert result.num_rows == 1
    end

    test "cascade deletes swipes when user is deleted" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Insert swipe
      %{num_rows: 1} =
        Repo.query!(
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
