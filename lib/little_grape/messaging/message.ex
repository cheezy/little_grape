defmodule LittleGrape.Messaging.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias LittleGrape.Accounts.User
  alias LittleGrape.Messaging.Conversation

  @max_content_length 2000

  schema "messages" do
    field :content, :string
    field :read_at, :utc_datetime

    belongs_to :conversation, Conversation
    belongs_to :sender, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def max_content_length, do: @max_content_length

  @doc """
  A changeset for creating a message record.
  Content is required and limited to 2000 characters.
  read_at is optional (nil means unread).
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :sender_id, :content, :read_at])
    |> validate_required([:conversation_id, :sender_id, :content])
    |> validate_length(:content, min: 1, max: @max_content_length)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
  end

  @doc """
  A changeset for marking a message as read.
  """
  def mark_read_changeset(message, read_at \\ DateTime.utc_now()) do
    message
    |> change(read_at: read_at)
  end
end
