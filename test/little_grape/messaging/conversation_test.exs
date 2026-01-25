defmodule LittleGrape.Messaging.ConversationTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging.Conversation
  alias LittleGrape.Repo

  defp create_match do
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

    match
  end

  describe "schema" do
    test "has expected fields" do
      fields = Conversation.__schema__(:fields)

      assert :id in fields
      assert :match_id in fields
      assert :inserted_at in fields
      assert :updated_at in fields
    end

    test "has belongs_to match association" do
      associations = Conversation.__schema__(:associations)

      assert :match in associations
    end

    test "has has_many messages association" do
      associations = Conversation.__schema__(:associations)

      assert :messages in associations
    end
  end

  describe "changeset/2" do
    test "valid changeset with match_id" do
      match = create_match()

      changeset = Conversation.changeset(%Conversation{}, %{match_id: match.id})

      assert changeset.valid?
    end

    test "invalid changeset when missing match_id" do
      changeset = Conversation.changeset(%Conversation{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).match_id
    end
  end

  describe "database integration" do
    test "can insert a valid conversation" do
      match = create_match()

      assert {:ok, conversation} =
               %Conversation{}
               |> Conversation.changeset(%{match_id: match.id})
               |> Repo.insert()

      assert conversation.id
      assert conversation.match_id == match.id
      assert conversation.inserted_at
      assert conversation.updated_at
    end

    test "enforces foreign key constraint on match_id" do
      non_existent_id = 999_999

      assert {:error, changeset} =
               %Conversation{}
               |> Conversation.changeset(%{match_id: non_existent_id})
               |> Repo.insert()

      assert "does not exist" in errors_on(changeset).match_id
    end

    test "enforces unique constraint on match_id" do
      match = create_match()

      # Insert first conversation
      assert {:ok, _conversation} =
               %Conversation{}
               |> Conversation.changeset(%{match_id: match.id})
               |> Repo.insert()

      # Try to insert duplicate
      assert {:error, changeset} =
               %Conversation{}
               |> Conversation.changeset(%{match_id: match.id})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).match_id
    end

    test "can preload match association" do
      match = create_match()

      {:ok, conversation} =
        %Conversation{}
        |> Conversation.changeset(%{match_id: match.id})
        |> Repo.insert()

      conversation = Repo.preload(conversation, :match)

      assert conversation.match.id == match.id
    end

    test "conversation is deleted when match is deleted" do
      match = create_match()

      {:ok, conversation} =
        %Conversation{}
        |> Conversation.changeset(%{match_id: match.id})
        |> Repo.insert()

      conversation_id = conversation.id

      # Delete the match
      Repo.delete!(match)

      # Conversation should be deleted too
      assert Repo.get(Conversation, conversation_id) == nil
    end
  end
end
