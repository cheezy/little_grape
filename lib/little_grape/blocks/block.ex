defmodule LittleGrape.Blocks.Block do
  use Ecto.Schema
  import Ecto.Changeset

  alias LittleGrape.Accounts.User

  schema "blocks" do
    belongs_to :blocker, User
    belongs_to :blocked, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  A changeset for creating a block record.
  Validates that blocker_id and blocked_id are different.
  """
  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_id, :blocked_id])
    |> validate_required([:blocker_id, :blocked_id])
    |> validate_not_self_block()
    |> foreign_key_constraint(:blocker_id)
    |> foreign_key_constraint(:blocked_id)
    |> unique_constraint([:blocker_id, :blocked_id])
    |> check_constraint(:blocker_id, name: :cannot_block_self, message: "cannot block yourself")
  end

  defp validate_not_self_block(changeset) do
    blocker_id = get_field(changeset, :blocker_id)
    blocked_id = get_field(changeset, :blocked_id)

    if blocker_id && blocked_id && blocker_id == blocked_id do
      add_error(changeset, :blocked_id, "cannot block yourself")
    else
      changeset
    end
  end
end
