defmodule LittleGrape.Swipes.Swipe do
  use Ecto.Schema
  import Ecto.Changeset

  alias LittleGrape.Accounts.User

  @action_options ["like", "pass"]

  schema "swipes" do
    field :action, :string

    belongs_to :user, User
    belongs_to :target_user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def action_options, do: @action_options

  @doc """
  A changeset for creating a swipe record.
  Validates that action is either 'like' or 'pass'.
  """
  def changeset(swipe, attrs) do
    swipe
    |> cast(attrs, [:user_id, :target_user_id, :action])
    |> validate_required([:user_id, :target_user_id, :action])
    |> validate_inclusion(:action, @action_options, message: "must be 'like' or 'pass'")
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:target_user_id)
    |> unique_constraint([:user_id, :target_user_id])
  end
end
