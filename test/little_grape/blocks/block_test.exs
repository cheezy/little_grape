defmodule LittleGrape.Blocks.BlockTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Blocks.Block
  alias LittleGrape.Repo

  describe "schema" do
    test "has expected fields" do
      fields = Block.__schema__(:fields)

      assert :id in fields
      assert :blocker_id in fields
      assert :blocked_id in fields
      assert :inserted_at in fields
    end

    test "does not have updated_at field" do
      fields = Block.__schema__(:fields)

      refute :updated_at in fields
    end

    test "has belongs_to blocker association" do
      associations = Block.__schema__(:associations)

      assert :blocker in associations
    end

    test "has belongs_to blocked association" do
      associations = Block.__schema__(:associations)

      assert :blocked in associations
    end
  end

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      blocker = user_fixture()
      blocked = user_fixture()

      attrs = %{
        blocker_id: blocker.id,
        blocked_id: blocked.id
      }

      changeset = Block.changeset(%Block{}, attrs)

      assert changeset.valid?
    end

    test "invalid changeset when missing blocker_id" do
      blocked = user_fixture()

      attrs = %{
        blocked_id: blocked.id
      }

      changeset = Block.changeset(%Block{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).blocker_id
    end

    test "invalid changeset when missing blocked_id" do
      blocker = user_fixture()

      attrs = %{
        blocker_id: blocker.id
      }

      changeset = Block.changeset(%Block{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).blocked_id
    end

    test "invalid changeset when blocker_id equals blocked_id" do
      user = user_fixture()

      attrs = %{
        blocker_id: user.id,
        blocked_id: user.id
      }

      changeset = Block.changeset(%Block{}, attrs)

      refute changeset.valid?
      assert "cannot block yourself" in errors_on(changeset).blocked_id
    end
  end

  describe "database integration" do
    test "can insert a valid block" do
      blocker = user_fixture()
      blocked = user_fixture()

      attrs = %{
        blocker_id: blocker.id,
        blocked_id: blocked.id
      }

      assert {:ok, block} =
               %Block{}
               |> Block.changeset(attrs)
               |> Repo.insert()

      assert block.id
      assert block.blocker_id == blocker.id
      assert block.blocked_id == blocked.id
      assert block.inserted_at
    end

    test "enforces foreign key constraint on blocker_id" do
      blocked = user_fixture()
      non_existent_id = 999_999

      assert {:error, changeset} =
               %Block{}
               |> Block.changeset(%{
                 blocker_id: non_existent_id,
                 blocked_id: blocked.id
               })
               |> Repo.insert()

      assert "does not exist" in errors_on(changeset).blocker_id
    end

    test "enforces foreign key constraint on blocked_id" do
      blocker = user_fixture()
      non_existent_id = 999_999

      assert {:error, changeset} =
               %Block{}
               |> Block.changeset(%{
                 blocker_id: blocker.id,
                 blocked_id: non_existent_id
               })
               |> Repo.insert()

      assert "does not exist" in errors_on(changeset).blocked_id
    end

    test "enforces unique constraint on blocker and blocked pair" do
      blocker = user_fixture()
      blocked = user_fixture()

      attrs = %{
        blocker_id: blocker.id,
        blocked_id: blocked.id
      }

      # Insert first block
      assert {:ok, _block} =
               %Block{}
               |> Block.changeset(attrs)
               |> Repo.insert()

      # Try to insert duplicate
      assert {:error, changeset} =
               %Block{}
               |> Block.changeset(attrs)
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).blocker_id
    end

    test "allows reverse block (A blocks B, B blocks A)" do
      user_a = user_fixture()
      user_b = user_fixture()

      # A blocks B
      assert {:ok, _block1} =
               %Block{}
               |> Block.changeset(%{blocker_id: user_a.id, blocked_id: user_b.id})
               |> Repo.insert()

      # B blocks A (different direction is allowed)
      assert {:ok, _block2} =
               %Block{}
               |> Block.changeset(%{blocker_id: user_b.id, blocked_id: user_a.id})
               |> Repo.insert()
    end

    test "can preload blocker association" do
      blocker = user_fixture()
      blocked = user_fixture()

      {:ok, block} =
        %Block{}
        |> Block.changeset(%{blocker_id: blocker.id, blocked_id: blocked.id})
        |> Repo.insert()

      block = Repo.preload(block, :blocker)

      assert block.blocker.id == blocker.id
    end

    test "can preload blocked association" do
      blocker = user_fixture()
      blocked = user_fixture()

      {:ok, block} =
        %Block{}
        |> Block.changeset(%{blocker_id: blocker.id, blocked_id: blocked.id})
        |> Repo.insert()

      block = Repo.preload(block, :blocked)

      assert block.blocked.id == blocked.id
    end

    test "block is deleted when blocker user is deleted" do
      blocker = user_fixture()
      blocked = user_fixture()

      {:ok, block} =
        %Block{}
        |> Block.changeset(%{blocker_id: blocker.id, blocked_id: blocked.id})
        |> Repo.insert()

      block_id = block.id

      # Delete the blocker
      Repo.delete!(blocker)

      # Block should be deleted too
      assert Repo.get(Block, block_id) == nil
    end

    test "block is deleted when blocked user is deleted" do
      blocker = user_fixture()
      blocked = user_fixture()

      {:ok, block} =
        %Block{}
        |> Block.changeset(%{blocker_id: blocker.id, blocked_id: blocked.id})
        |> Repo.insert()

      block_id = block.id

      # Delete the blocked user
      Repo.delete!(blocked)

      # Block should be deleted too
      assert Repo.get(Block, block_id) == nil
    end
  end
end
