defmodule LittleGrape.Repo.Migrations.AddUnreadMessagesPartialIndex do
  use Ecto.Migration

  def change do
    create index(:messages, [:conversation_id],
             where: "read_at IS NULL",
             name: :messages_conversation_id_unread_index
           )
  end
end
