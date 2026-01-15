defmodule LittleGrape.Repo.Migrations.CreateProfiles do
  use Ecto.Migration

  def change do
    create table(:profiles) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Basic info
      add :first_name, :string, size: 50
      add :last_name, :string, size: 50
      add :birthdate, :date
      add :gender, :string, size: 20
      add :city, :string, size: 100
      add :country, :string, size: 100

      # About me
      add :bio, :text
      add :interests, {:array, :string}, default: []
      add :occupation, :string, size: 100

      # Physical attributes
      add :height_cm, :integer
      add :body_type, :string, size: 20
      add :eye_color, :string, size: 20
      add :hair_color, :string, size: 20

      # Preferences
      add :looking_for, :string, size: 20
      add :preferred_age_min, :integer
      add :preferred_age_max, :integer
      add :preferred_distance_km, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:profiles, [:user_id])
  end
end
