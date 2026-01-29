defmodule LittleGrape.MatchesTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Matches
  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Messaging.Message

  describe "create_match/2" do
    test "creates match with correct user order when user_a_id < user_b_id" do
      user1 = user_fixture()
      user2 = user_fixture()

      {smaller_id, larger_id} =
        if user1.id < user2.id, do: {user1.id, user2.id}, else: {user2.id, user1.id}

      assert {:ok, %{match: match, conversation: _conversation}} =
               Matches.create_match(smaller_id, larger_id)

      assert %Match{} = match
      assert match.user_a_id == smaller_id
      assert match.user_b_id == larger_id
      assert match.matched_at != nil
    end

    test "normalizes user IDs when user_a_id > user_b_id" do
      user1 = user_fixture()
      user2 = user_fixture()

      {smaller_id, larger_id} =
        if user1.id < user2.id, do: {user1.id, user2.id}, else: {user2.id, user1.id}

      # Pass IDs in wrong order (larger first)
      assert {:ok, %{match: match, conversation: _conversation}} =
               Matches.create_match(larger_id, smaller_id)

      # Match should have normalized order
      assert match.user_a_id == smaller_id
      assert match.user_b_id == larger_id
    end

    test "creates conversation linked to match" do
      user1 = user_fixture()
      user2 = user_fixture()

      assert {:ok, %{match: match, conversation: conversation}} =
               Matches.create_match(user1.id, user2.id)

      assert %Conversation{} = conversation
      assert conversation.match_id == match.id
    end

    test "transaction rolls back on duplicate match attempt" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Create first match
      assert {:ok, _result} = Matches.create_match(user1.id, user2.id)

      # Attempt duplicate match
      assert {:error, :match, changeset, %{}} = Matches.create_match(user1.id, user2.id)
      assert "has already been taken" in errors_on(changeset).user_a_id
    end

    test "returns error when a user does not exist" do
      user = user_fixture()
      non_existent_id = 999_999

      # After normalization, the non_existent_id (999_999) will be user_b_id
      # since it's larger than any real user ID
      assert {:error, :match, changeset, %{}} = Matches.create_match(non_existent_id, user.id)
      assert "does not exist" in errors_on(changeset).user_b_id
    end

    test "returns error when the other user does not exist" do
      user = user_fixture()
      non_existent_id = 999_999

      assert {:error, :match, changeset, %{}} = Matches.create_match(user.id, non_existent_id)
      assert "does not exist" in errors_on(changeset).user_b_id
    end

    test "sets matched_at timestamp" do
      user1 = user_fixture()
      user2 = user_fixture()

      assert {:ok, %{match: match, conversation: _conversation}} =
               Matches.create_match(user1.id, user2.id)

      assert %DateTime{} = match.matched_at
      # Verify it's a recent timestamp (within the last minute)
      diff = DateTime.diff(DateTime.utc_now(), match.matched_at, :second)
      assert diff >= 0 and diff < 60
    end

    test "both match and conversation are created in a single transaction" do
      user1 = user_fixture()
      user2 = user_fixture()

      assert {:ok, %{match: match, conversation: conversation}} =
               Matches.create_match(user1.id, user2.id)

      # Verify both records exist in the database
      assert Repo.get(Match, match.id) != nil
      assert Repo.get(Conversation, conversation.id) != nil
    end
  end

  describe "list_matches/1" do
    test "returns matches where user is user_a" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: _conversation}} =
        Matches.create_match(user1.id, user2.id)

      {user_a, _user_b} = if user1.id < user2.id, do: {user1, user2}, else: {user2, user1}

      matches = Matches.list_matches(user_a)
      assert length(matches) == 1
      assert hd(matches).id == match.id
    end

    test "returns matches where user is user_b" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: _conversation}} =
        Matches.create_match(user1.id, user2.id)

      {_user_a, user_b} = if user1.id < user2.id, do: {user1, user2}, else: {user2, user1}

      matches = Matches.list_matches(user_b)
      assert length(matches) == 1
      assert hd(matches).id == match.id
    end

    test "returns empty list when user has no matches" do
      user = user_fixture()

      assert Matches.list_matches(user) == []
    end

    test "returns multiple matches for same user" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, %{match: match1, conversation: _}} = Matches.create_match(user1.id, user2.id)
      {:ok, %{match: match2, conversation: _}} = Matches.create_match(user1.id, user3.id)

      matches = Matches.list_matches(user1)
      assert length(matches) == 2
      match_ids = Enum.map(matches, & &1.id)
      assert match1.id in match_ids
      assert match2.id in match_ids
    end

    test "does not return other users' matches" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()
      user4 = user_fixture()

      # Match between user1 and user2
      {:ok, _} = Matches.create_match(user1.id, user2.id)
      # Match between user3 and user4
      {:ok, _} = Matches.create_match(user3.id, user4.id)

      # user1 should only see their match, not user3/user4's match
      matches = Matches.list_matches(user1)
      assert length(matches) == 1
    end
  end

  describe "get_match/2" do
    test "returns match when user is participant (user_a)" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: _}} = Matches.create_match(user1.id, user2.id)

      {user_a, _user_b} = if user1.id < user2.id, do: {user1, user2}, else: {user2, user1}

      fetched_match = Matches.get_match(user_a, match.id)
      assert fetched_match.id == match.id
    end

    test "returns match when user is participant (user_b)" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: _}} = Matches.create_match(user1.id, user2.id)

      {_user_a, user_b} = if user1.id < user2.id, do: {user1, user2}, else: {user2, user1}

      fetched_match = Matches.get_match(user_b, match.id)
      assert fetched_match.id == match.id
    end

    test "returns nil when user is not a participant" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, %{match: match, conversation: _}} = Matches.create_match(user1.id, user2.id)

      # user3 is not a participant in the match
      assert Matches.get_match(user3, match.id) == nil
    end

    test "returns nil for non-existent match" do
      user = user_fixture()
      non_existent_id = 999_999

      assert Matches.get_match(user, non_existent_id) == nil
    end
  end

  describe "unmatch/2" do
    test "removes match when user is participant" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: _}} = Matches.create_match(user1.id, user2.id)

      assert :ok = Matches.unmatch(user1, match.id)
      assert Repo.get(Match, match.id) == nil
    end

    test "returns error when user is not a participant" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, %{match: match, conversation: _}} = Matches.create_match(user1.id, user2.id)

      # user3 is not a participant
      assert {:error, :not_found} = Matches.unmatch(user3, match.id)
      # Match should still exist
      assert Repo.get(Match, match.id) != nil
    end

    test "returns error for non-existent match" do
      user = user_fixture()
      non_existent_id = 999_999

      assert {:error, :not_found} = Matches.unmatch(user, non_existent_id)
    end

    test "cascade deletes conversation when match is deleted" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user1.id, user2.id)

      assert :ok = Matches.unmatch(user1, match.id)
      assert Repo.get(Conversation, conversation.id) == nil
    end

    test "cascade deletes messages when match is deleted" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, %{match: match, conversation: conversation}} =
        Matches.create_match(user1.id, user2.id)

      # Create a message in the conversation
      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          conversation_id: conversation.id,
          sender_id: user1.id,
          content: "Hello!"
        })
        |> Repo.insert()

      assert :ok = Matches.unmatch(user1, match.id)
      assert Repo.get(Message, message.id) == nil
    end

    test "either user can unmatch" do
      user1 = user_fixture()
      user2 = user_fixture()

      # First match - user1 unmatches
      {:ok, %{match: match1, conversation: _}} = Matches.create_match(user1.id, user2.id)
      assert :ok = Matches.unmatch(user1, match1.id)

      # Second match - user2 unmatches
      {:ok, %{match: match2, conversation: _}} = Matches.create_match(user1.id, user2.id)
      assert :ok = Matches.unmatch(user2, match2.id)
    end
  end
end
