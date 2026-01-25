defmodule LittleGrape.Matches.Match do
  use Ecto.Schema
  import Ecto.Changeset

  alias LittleGrape.Accounts.User

  schema "matches" do
    field :matched_at, :utc_datetime

    belongs_to :user_a, User
    belongs_to :user_b, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for creating a match record.
  Validates that user_a_id < user_b_id for consistent ordering.
  """
  def changeset(match, attrs) do
    match
    |> cast(attrs, [:user_a_id, :user_b_id, :matched_at])
    |> validate_required([:user_a_id, :user_b_id, :matched_at])
    |> validate_user_ordering()
    |> foreign_key_constraint(:user_a_id)
    |> foreign_key_constraint(:user_b_id)
    |> unique_constraint([:user_a_id, :user_b_id])
  end

  defp validate_user_ordering(changeset) do
    user_a_id = get_field(changeset, :user_a_id)
    user_b_id = get_field(changeset, :user_b_id)

    if user_a_id && user_b_id && user_a_id >= user_b_id do
      add_error(changeset, :user_a_id, "must be less than user_b_id")
    else
      changeset
    end
  end

  @doc """
  Normalizes user IDs to ensure user_a_id < user_b_id.
  Returns {smaller_id, larger_id}.
  """
  def normalize_user_ids(id1, id2) when id1 < id2, do: {id1, id2}
  def normalize_user_ids(id1, id2), do: {id2, id1}
end
