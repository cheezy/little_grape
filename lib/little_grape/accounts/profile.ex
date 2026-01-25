defmodule LittleGrape.Accounts.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  alias LittleGrape.Accounts.User

  schema "profiles" do
    # Basic info
    field :first_name, :string
    field :last_name, :string
    field :birthdate, :date
    field :gender, :string
    field :city, :string
    field :country, :string

    # About me
    field :bio, :string
    field :interests, {:array, :string}, default: []
    field :occupation, :string

    # Lifestyle & Habits
    field :smoking, :string
    field :drinking, :string
    field :has_children, :boolean
    field :wants_children, :string

    # Background
    field :education, :string
    field :religion, :string
    field :languages, {:array, :string}, default: []

    # Physical attributes
    field :height_cm, :integer
    field :body_type, :string
    field :eye_color, :string
    field :hair_color, :string

    # Preferences
    field :looking_for, :string
    field :preferred_gender, :string
    field :preferred_age_min, :integer
    field :preferred_age_max, :integer
    field :preferred_country, :string

    # Profile picture
    field :profile_picture, :string

    # Other languages (when "other" is selected)
    field :other_languages, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @gender_options ["male", "female", "other"]
  @body_type_options ["slim", "athletic", "average", "curvy", "muscular", "plus_size"]
  @eye_color_options ["brown", "blue", "green", "hazel", "gray", "black"]
  @hair_color_options ["black", "brown", "blonde", "red", "gray", "white", "other"]
  @looking_for_options ["friendship", "dating", "relationship", "marriage", "not_sure"]
  @country_options [
    "AL",
    "XK",
    "MK",
    "ME",
    "RS",
    "BA",
    "HR",
    "SI",
    "GR",
    "IT",
    "AT",
    "DE",
    "CH",
    "BE",
    "NL",
    "FR",
    "GB",
    "US",
    "CA",
    "AU",
    "SE",
    "NO",
    "DK",
    "FI",
    "ES",
    "PT",
    "TR",
    "CY",
    "MT",
    "other"
  ]

  # Lifestyle options
  @smoking_options ["non_smoker", "occasional", "regular"]
  @drinking_options ["non_drinker", "social", "regular"]
  @wants_children_options ["yes", "no", "maybe", "have_and_want_more"]

  # Background options
  @education_options ["high_school", "some_college", "bachelors", "masters", "doctorate", "other"]
  @religion_options ["muslim", "orthodox", "catholic", "atheist", "other", "prefer_not_to_say"]
  @language_options ["sq", "en", "it", "de", "fr", "sr", "mk", "tr", "other"]

  # Interest options
  @interest_options [
    "sports",
    "music",
    "travel",
    "reading",
    "cooking",
    "movies",
    "fitness",
    "art",
    "nature",
    "technology",
    "gaming",
    "photography",
    "dancing",
    "fashion"
  ]

  def gender_options, do: @gender_options
  def body_type_options, do: @body_type_options
  def eye_color_options, do: @eye_color_options
  def hair_color_options, do: @hair_color_options
  def looking_for_options, do: @looking_for_options
  def country_options, do: @country_options
  def smoking_options, do: @smoking_options
  def drinking_options, do: @drinking_options
  def wants_children_options, do: @wants_children_options
  def education_options, do: @education_options
  def religion_options, do: @religion_options
  def language_options, do: @language_options
  def interest_options, do: @interest_options

  @doc """
  A profile changeset for creating or updating profile information.
  """
  @castable_fields [
    :first_name,
    :last_name,
    :birthdate,
    :gender,
    :city,
    :country,
    :bio,
    :interests,
    :occupation,
    :smoking,
    :drinking,
    :has_children,
    :wants_children,
    :education,
    :religion,
    :languages,
    :height_cm,
    :body_type,
    :eye_color,
    :hair_color,
    :looking_for,
    :preferred_gender,
    :preferred_age_min,
    :preferred_age_max,
    :preferred_country,
    :other_languages
  ]

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @castable_fields)
    |> validate_lengths()
    |> validate_options()
    |> validate_numbers()
    |> validate_birthdate()
    |> validate_age_range()
  end

  defp validate_lengths(changeset) do
    changeset
    |> validate_length(:first_name, max: 50)
    |> validate_length(:last_name, max: 50)
    |> validate_length(:bio, max: 1000)
    |> validate_length(:occupation, max: 100)
    |> validate_length(:city, max: 100)
    |> validate_length(:other_languages, max: 255)
  end

  defp validate_options(changeset) do
    changeset
    |> validate_inclusion(:gender, @gender_options)
    |> validate_inclusion(:country, @country_options)
    |> validate_inclusion(:body_type, @body_type_options)
    |> validate_inclusion(:eye_color, @eye_color_options)
    |> validate_inclusion(:hair_color, @hair_color_options)
    |> validate_inclusion(:looking_for, @looking_for_options)
    |> validate_inclusion(:preferred_gender, @gender_options ++ ["any"])
    |> validate_inclusion(:preferred_country, @country_options)
    |> validate_inclusion(:smoking, @smoking_options)
    |> validate_inclusion(:drinking, @drinking_options)
    |> validate_inclusion(:wants_children, @wants_children_options)
    |> validate_inclusion(:education, @education_options)
    |> validate_inclusion(:religion, @religion_options)
    |> validate_subset(:languages, @language_options)
    |> validate_subset(:interests, @interest_options)
  end

  defp validate_numbers(changeset) do
    changeset
    |> validate_number(:height_cm, greater_than: 100, less_than: 250)
    |> validate_number(:preferred_age_min, greater_than_or_equal_to: 18, less_than: 100)
    |> validate_number(:preferred_age_max, greater_than_or_equal_to: 18, less_than: 100)
  end

  defp validate_birthdate(changeset) do
    case get_change(changeset, :birthdate) do
      nil ->
        changeset

      birthdate ->
        today = Date.utc_today()
        min_date = Date.add(today, -100 * 365)
        max_date = Date.add(today, -18 * 365)

        cond do
          Date.compare(birthdate, min_date) == :lt ->
            add_error(changeset, :birthdate, "is too far in the past")

          Date.compare(birthdate, max_date) == :gt ->
            add_error(changeset, :birthdate, "you must be at least 18 years old")

          true ->
            changeset
        end
    end
  end

  defp validate_age_range(changeset) do
    min_age = get_field(changeset, :preferred_age_min)
    max_age = get_field(changeset, :preferred_age_max)

    if min_age && max_age && min_age > max_age do
      add_error(changeset, :preferred_age_max, "must be greater than or equal to minimum age")
    else
      changeset
    end
  end

  @doc """
  A changeset for updating the profile picture.
  """
  def profile_picture_changeset(profile, attrs) do
    profile
    |> cast(attrs, [:profile_picture])
  end
end
