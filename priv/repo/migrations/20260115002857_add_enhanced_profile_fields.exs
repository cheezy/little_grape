defmodule LittleGrape.Repo.Migrations.AddEnhancedProfileFields do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      # Lifestyle & Habits
      add :smoking, :string, size: 20
      add :drinking, :string, size: 20
      add :has_children, :boolean
      add :wants_children, :string, size: 20

      # Background
      add :education, :string, size: 30
      add :religion, :string, size: 30
      add :languages, {:array, :string}, default: []

      # Match Preferences
      add :preferred_gender, :string, size: 10
    end
  end
end
