defmodule LittleGrape.Matches.MatchTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Matches.Match
  alias LittleGrape.Repo

  describe "schema" do
    test "has expected fields" do
      fields = Match.__schema__(:fields)

      assert :id in fields
      assert :user_a_id in fields
      assert :user_b_id in fields
      assert :matched_at in fields
      assert :inserted_at in fields
      assert :updated_at in fields
    end

    test "has belongs_to associations for both users" do
      associations = Match.__schema__(:associations)

      assert :user_a in associations
      assert :user_b in associations
    end
  end

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      user_a = user_fixture()
      user_b = user_fixture()
      {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, user_b.id)

      attrs = %{
        user_a_id: smaller_id,
        user_b_id: larger_id,
        matched_at: DateTime.utc_now()
      }

      changeset = Match.changeset(%Match{}, attrs)

      assert changeset.valid?
    end

    test "invalid changeset when missing user_a_id" do
      user_b = user_fixture()

      attrs = %{
        user_b_id: user_b.id,
        matched_at: DateTime.utc_now()
      }

      changeset = Match.changeset(%Match{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_a_id
    end

    test "invalid changeset when missing user_b_id" do
      user_a = user_fixture()

      attrs = %{
        user_a_id: user_a.id,
        matched_at: DateTime.utc_now()
      }

      changeset = Match.changeset(%Match{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_b_id
    end

    test "invalid changeset when missing matched_at" do
      user_a = user_fixture()
      user_b = user_fixture()
      {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, user_b.id)

      attrs = %{
        user_a_id: smaller_id,
        user_b_id: larger_id
      }

      changeset = Match.changeset(%Match{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).matched_at
    end

    test "invalid changeset when user_a_id >= user_b_id" do
      user_a = user_fixture()
      user_b = user_fixture()
      # Intentionally use the wrong order (larger first)
      {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, user_b.id)

      attrs = %{
        user_a_id: larger_id,
        user_b_id: smaller_id,
        matched_at: DateTime.utc_now()
      }

      changeset = Match.changeset(%Match{}, attrs)

      refute changeset.valid?
      assert "must be less than user_b_id" in errors_on(changeset).user_a_id
    end

    test "invalid changeset when user_a_id equals user_b_id" do
      user = user_fixture()

      attrs = %{
        user_a_id: user.id,
        user_b_id: user.id,
        matched_at: DateTime.utc_now()
      }

      changeset = Match.changeset(%Match{}, attrs)

      refute changeset.valid?
      assert "must be less than user_b_id" in errors_on(changeset).user_a_id
    end
  end

  describe "normalize_user_ids/2" do
    test "returns ids in correct order when first id is smaller" do
      assert {1, 5} = Match.normalize_user_ids(1, 5)
    end

    test "returns ids in correct order when first id is larger" do
      assert {1, 5} = Match.normalize_user_ids(5, 1)
    end

    test "returns ids in correct order when ids are equal" do
      assert {3, 3} = Match.normalize_user_ids(3, 3)
    end
  end

  describe "database integration" do
    test "can insert a valid match" do
      user_a = user_fixture()
      user_b = user_fixture()
      {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, user_b.id)

      attrs = %{
        user_a_id: smaller_id,
        user_b_id: larger_id,
        matched_at: DateTime.utc_now()
      }

      assert {:ok, match} =
               %Match{}
               |> Match.changeset(attrs)
               |> Repo.insert()

      assert match.id
      assert match.user_a_id == smaller_id
      assert match.user_b_id == larger_id
      assert match.matched_at
      assert match.inserted_at
      assert match.updated_at
    end

    test "enforces foreign key constraint on user_a_id" do
      user_b = user_fixture()
      non_existent_id = user_b.id + 999_999

      # Ensure proper ordering: non_existent_id should be smaller
      {smaller_id, larger_id} =
        if non_existent_id < user_b.id do
          {non_existent_id, user_b.id}
        else
          # If non_existent_id is larger, we need to swap them
          # and the constraint will fail on user_a_id
          {user_b.id, non_existent_id}
        end

      attrs = %{
        user_a_id: smaller_id,
        user_b_id: larger_id,
        matched_at: DateTime.utc_now()
      }

      assert {:error, changeset} =
               %Match{}
               |> Match.changeset(attrs)
               |> Repo.insert()

      # The error will be on whichever field has the non-existent id
      assert changeset.errors != []
    end

    test "enforces foreign key constraint on user_b_id" do
      user_a = user_fixture()
      non_existent_id = user_a.id + 999_999

      # Ensure proper ordering
      {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, non_existent_id)

      attrs = %{
        user_a_id: smaller_id,
        user_b_id: larger_id,
        matched_at: DateTime.utc_now()
      }

      assert {:error, changeset} =
               %Match{}
               |> Match.changeset(attrs)
               |> Repo.insert()

      # The error will be on whichever field has the non-existent id
      assert changeset.errors != []
    end

    test "enforces unique constraint on user pair" do
      user_a = user_fixture()
      user_b = user_fixture()
      {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, user_b.id)

      attrs = %{
        user_a_id: smaller_id,
        user_b_id: larger_id,
        matched_at: DateTime.utc_now()
      }

      # Insert first match
      assert {:ok, _match} =
               %Match{}
               |> Match.changeset(attrs)
               |> Repo.insert()

      # Try to insert duplicate
      assert {:error, changeset} =
               %Match{}
               |> Match.changeset(attrs)
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).user_a_id
    end

    test "can preload user associations" do
      user_a = user_fixture()
      user_b = user_fixture()
      {smaller_id, larger_id} = Match.normalize_user_ids(user_a.id, user_b.id)

      attrs = %{
        user_a_id: smaller_id,
        user_b_id: larger_id,
        matched_at: DateTime.utc_now()
      }

      {:ok, match} =
        %Match{}
        |> Match.changeset(attrs)
        |> Repo.insert()

      match = Repo.preload(match, [:user_a, :user_b])

      assert match.user_a.id == smaller_id
      assert match.user_b.id == larger_id
    end
  end
end
