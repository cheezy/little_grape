defmodule LittleGrape.Swipes.SwipeTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Repo
  alias LittleGrape.Swipes.Swipe

  describe "Swipe schema" do
    test "has correct fields" do
      swipe = %Swipe{}
      assert Map.has_key?(swipe, :user_id)
      assert Map.has_key?(swipe, :target_user_id)
      assert Map.has_key?(swipe, :action)
      assert Map.has_key?(swipe, :inserted_at)
    end

    test "action_options returns valid options" do
      assert Swipe.action_options() == ["like", "pass"]
    end
  end

  describe "changeset/2" do
    test "valid changeset with 'like' action" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: "like"}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      assert changeset.valid?
    end

    test "valid changeset with 'pass' action" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: "pass"}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      assert changeset.valid?
    end

    test "invalid changeset with invalid action" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: "superlike"}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      refute changeset.valid?
      assert "must be 'like' or 'pass'" in errors_on(changeset).action
    end

    test "invalid changeset without action" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).action
    end

    test "invalid changeset without user_id" do
      target_user = user_fixture()

      attrs = %{target_user_id: target_user.id, action: "like"}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "invalid changeset without target_user_id" do
      user = user_fixture()

      attrs = %{user_id: user.id, action: "like"}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).target_user_id
    end

    test "rejects empty string action" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: ""}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      refute changeset.valid?
    end

    test "rejects nil action" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: nil}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      refute changeset.valid?
    end
  end

  describe "database integration" do
    test "can insert valid swipe record" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: "like"}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      assert {:ok, swipe} = Repo.insert(changeset)
      assert swipe.user_id == user.id
      assert swipe.target_user_id == target_user.id
      assert swipe.action == "like"
      assert swipe.inserted_at != nil
    end

    test "can preload user association" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: "like"}
      {:ok, swipe} = %Swipe{} |> Swipe.changeset(attrs) |> Repo.insert()

      swipe_with_user = Repo.preload(swipe, :user)
      assert swipe_with_user.user.id == user.id
      assert swipe_with_user.user.email == user.email
    end

    test "can preload target_user association" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: "pass"}
      {:ok, swipe} = %Swipe{} |> Swipe.changeset(attrs) |> Repo.insert()

      swipe_with_target = Repo.preload(swipe, :target_user)
      assert swipe_with_target.target_user.id == target_user.id
      assert swipe_with_target.target_user.email == target_user.email
    end

    test "unique constraint prevents duplicate swipes" do
      user = user_fixture()
      target_user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: target_user.id, action: "like"}
      {:ok, _swipe} = %Swipe{} |> Swipe.changeset(attrs) |> Repo.insert()

      # Try to insert duplicate
      duplicate_attrs = %{user_id: user.id, target_user_id: target_user.id, action: "pass"}
      changeset = Swipe.changeset(%Swipe{}, duplicate_attrs)

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).user_id
    end

    test "foreign key constraint on user_id" do
      target_user = user_fixture()

      attrs = %{user_id: -1, target_user_id: target_user.id, action: "like"}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).user_id
    end

    test "foreign key constraint on target_user_id" do
      user = user_fixture()

      attrs = %{user_id: user.id, target_user_id: -1, action: "like"}
      changeset = Swipe.changeset(%Swipe{}, attrs)

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).target_user_id
    end
  end
end
