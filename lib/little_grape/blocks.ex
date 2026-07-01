defmodule LittleGrape.Blocks do
  @moduledoc """
  The Blocks context.
  """

  import Ecto.Query, warn: false

  alias LittleGrape.Accounts.User
  alias LittleGrape.Blocks.Block
  alias LittleGrape.Repo

  @doc """
  Blocks another user on behalf of the given user.

  Blocking is idempotent: blocking a user who is already blocked succeeds and
  returns the existing block.

  ## Parameters

    * `user` - The user performing the block (struct with id)
    * `blocked_user_id` - The ID of the user being blocked

  ## Returns

    * `{:ok, %Block{}}` - Block created (or already existed)
    * `{:error, %Ecto.Changeset{}}` - Self-block or missing user
    * `{:error, :not_found}` - Race only: the existing block was deleted
      between the conflicting insert and the follow-up fetch

  ## Examples

      iex> block_user(user, other_id)
      {:ok, %Block{}}

      iex> block_user(user, other_id)  # already blocked
      {:ok, %Block{}}

      iex> block_user(user, user.id)
      {:error, %Ecto.Changeset{}}

  """
  def block_user(%User{id: blocker_id}, blocked_user_id) do
    changeset =
      Block.changeset(%Block{}, %{blocker_id: blocker_id, blocked_id: blocked_user_id})

    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:blocker_id, :blocked_id]
         ) do
      {:ok, %Block{id: nil}} ->
        # Conflict: the block already exists — return the existing record.
        case Repo.get_by(Block, blocker_id: blocker_id, blocked_id: blocked_user_id) do
          nil -> {:error, :not_found}
          block -> {:ok, block}
        end

      other ->
        other
    end
  end

  @doc """
  Removes the given user's block on another user.

  Only removes the caller's own block; a block in the other direction is
  untouched.

  ## Parameters

    * `user` - The user removing their block (struct with id)
    * `blocked_user_id` - The ID of the previously blocked user

  ## Returns

    * `{:ok, %Block{}}` - Block removed
    * `{:error, :not_found}` - No block by this user on the target

  ## Examples

      iex> unblock_user(user, other_id)
      {:ok, %Block{}}

      iex> unblock_user(user, never_blocked_id)
      {:error, :not_found}

  """
  def unblock_user(%User{id: blocker_id}, blocked_user_id) do
    case Repo.get_by(Block, blocker_id: blocker_id, blocked_id: blocked_user_id) do
      nil -> {:error, :not_found}
      block -> Repo.delete(block)
    end
  end

  @doc """
  Checks whether a block exists between two users in either direction.

  Blocking is a safety feature: a block by either user severs the connection
  for both, so this check is intentionally bidirectional.

  ## Parameters

    * `user_id` - One user's ID
    * `other_user_id` - The other user's ID

  ## Returns

    * `true` - Either user has blocked the other
    * `false` - No block exists between the users

  ## Examples

      iex> blocked?(user_id, blocked_or_blocker_id)
      true

      iex> blocked?(user_id, stranger_id)
      false

  """
  def blocked?(user_id, other_user_id) do
    from(b in Block,
      where:
        (b.blocker_id == ^user_id and b.blocked_id == ^other_user_id) or
          (b.blocker_id == ^other_user_id and b.blocked_id == ^user_id)
    )
    |> Repo.exists?()
  end
end
