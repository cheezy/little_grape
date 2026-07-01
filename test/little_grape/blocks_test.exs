defmodule LittleGrape.BlocksTest do
  use LittleGrape.DataCase, async: true

  import LittleGrape.AccountsFixtures

  alias LittleGrape.Blocks
  alias LittleGrape.Blocks.Block
  alias LittleGrape.Repo

  describe "block_user/2" do
    test "creates a block" do
      blocker = user_fixture()
      blocked = user_fixture()

      assert {:ok, %Block{} = block} = Blocks.block_user(blocker, blocked.id)
      assert block.blocker_id == blocker.id
      assert block.blocked_id == blocked.id
      assert Blocks.blocked?(blocker.id, blocked.id)
    end

    test "is idempotent on duplicate blocks" do
      blocker = user_fixture()
      blocked = user_fixture()

      assert {:ok, %Block{id: block_id}} = Blocks.block_user(blocker, blocked.id)
      assert {:ok, %Block{id: ^block_id}} = Blocks.block_user(blocker, blocked.id)
      assert Repo.aggregate(Block, :count) == 1
    end

    test "rejects blocking yourself" do
      user = user_fixture()

      assert {:error, changeset} = Blocks.block_user(user, user.id)
      assert "cannot block yourself" in errors_on(changeset).blocked_id
    end

    test "returns an error changeset when the blocked user does not exist" do
      user = user_fixture()

      assert {:error, changeset} = Blocks.block_user(user, 999_999)
      assert "does not exist" in errors_on(changeset).blocked_id
    end
  end

  describe "unblock_user/2" do
    test "removes an existing block" do
      blocker = user_fixture()
      blocked = user_fixture()

      assert {:ok, _block} = Blocks.block_user(blocker, blocked.id)
      assert {:ok, %Block{}} = Blocks.unblock_user(blocker, blocked.id)
      refute Blocks.blocked?(blocker.id, blocked.id)
    end

    test "returns {:error, :not_found} when no block exists" do
      user = user_fixture()
      other = user_fixture()

      assert {:error, :not_found} = Blocks.unblock_user(user, other.id)
    end

    test "only removes the caller's own block direction" do
      user_a = user_fixture()
      user_b = user_fixture()

      assert {:ok, _block} = Blocks.block_user(user_a, user_b.id)
      assert {:ok, _block} = Blocks.block_user(user_b, user_a.id)

      assert {:ok, %Block{}} = Blocks.unblock_user(user_a, user_b.id)

      # B's block on A remains, so the pair is still blocked
      assert Blocks.blocked?(user_a.id, user_b.id)
    end
  end

  describe "blocked?/2" do
    test "returns true when the first user blocked the second" do
      blocker = user_fixture()
      blocked = user_fixture()

      assert {:ok, _block} = Blocks.block_user(blocker, blocked.id)
      assert Blocks.blocked?(blocker.id, blocked.id)
    end

    test "returns true when the second user blocked the first" do
      blocker = user_fixture()
      blocked = user_fixture()

      assert {:ok, _block} = Blocks.block_user(blocker, blocked.id)
      assert Blocks.blocked?(blocked.id, blocker.id)
    end

    test "returns false when no block exists between the users" do
      user = user_fixture()
      other = user_fixture()

      refute Blocks.blocked?(user.id, other.id)
    end
  end
end
