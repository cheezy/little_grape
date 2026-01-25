defmodule LittleGrape.Messaging.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias LittleGrape.Matches.Match
  alias LittleGrape.Messaging.Message

  schema "conversations" do
    belongs_to :match, Match
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for creating a conversation record.
  Each match can only have one conversation (enforced by unique index).
  """
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:match_id])
    |> validate_required([:match_id])
    |> foreign_key_constraint(:match_id)
    |> unique_constraint(:match_id)
  end
end
