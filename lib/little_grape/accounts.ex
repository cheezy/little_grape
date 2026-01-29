defmodule LittleGrape.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias LittleGrape.Accounts.Profile
  alias LittleGrape.Accounts.User
  alias LittleGrape.Accounts.UserNotifier
  alias LittleGrape.Accounts.UserToken
  alias LittleGrape.Repo

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `LittleGrape.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `LittleGrape.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. Password params can be passed
     to set the password during confirmation.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token, password_params \\ %{}) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        changeset =
          user
          |> User.confirm_changeset()
          |> User.password_changeset(password_params)

        if changeset.valid? do
          update_user_and_delete_all_tokens(changeset)
        else
          {:error, changeset}
        end

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    UserToken
    |> from(where: [token: ^token, context: "session"])
    |> Repo.delete_all()

    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Profile

  @doc """
  Gets a user's profile.

  Returns nil if the profile doesn't exist.
  """
  def get_profile(user) do
    Repo.get_by(Profile, user_id: user.id)
  end

  @doc """
  Gets a user's profile or creates an empty one if it doesn't exist.
  """
  def get_or_create_profile(user) do
    case get_profile(user) do
      nil ->
        %Profile{}
        |> Ecto.Changeset.change(user_id: user.id)
        |> Repo.insert!()

      profile ->
        profile
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user profile.

  ## Examples

      iex> change_profile(profile)
      %Ecto.Changeset{data: %Profile{}}

  """
  def change_profile(%Profile{} = profile, attrs \\ %{}) do
    Profile.changeset(profile, attrs)
  end

  @doc """
  Updates the user profile.

  ## Examples

      iex> update_profile(profile, %{field: new_value})
      {:ok, %Profile{}}

      iex> update_profile(profile, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_profile(%Profile{} = profile, attrs) do
    profile
    |> Profile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the profile picture.

  Accepts a Plug.Upload struct and saves the file to the uploads directory.
  Returns the updated profile or error changeset.
  """
  @allowed_image_extensions ~w(.jpg .jpeg .png .gif .webp)

  # sobelow_skip ["Traversal"]
  def update_profile_picture(%Profile{} = profile, %Plug.Upload{} = upload) do
    extension = upload.filename |> Path.extname() |> String.downcase()

    if extension in @allowed_image_extensions do
      uploads_dir = uploads_directory()
      File.mkdir_p!(uploads_dir)

      # Generate safe filename using only profile ID and timestamp
      filename = "#{profile.id}_#{System.system_time(:second)}#{extension}"
      dest_path = Path.join(uploads_dir, filename)

      case File.cp(upload.path, dest_path) do
        :ok ->
          delete_old_picture(profile, uploads_dir)

          profile
          |> Profile.profile_picture_changeset(%{
            profile_picture: "/uploads/profile_pictures/#{filename}"
          })
          |> Repo.update()

        {:error, reason} ->
          changeset =
            profile
            |> Profile.profile_picture_changeset(%{})
            |> Ecto.Changeset.add_error(:profile_picture, "failed to upload: #{reason}")

          {:error, changeset}
      end
    else
      changeset =
        profile
        |> Profile.profile_picture_changeset(%{})
        |> Ecto.Changeset.add_error(:profile_picture, "invalid file type")

      {:error, changeset}
    end
  end

  def update_profile_picture(%Profile{} = profile, nil), do: {:ok, profile}

  # sobelow_skip ["Traversal"]
  defp delete_old_picture(profile, uploads_dir) do
    if profile.profile_picture do
      # Use Path.basename to prevent directory traversal
      old_filename = Path.basename(profile.profile_picture)
      old_path = Path.join(uploads_dir, old_filename)

      # Verify the path is still within uploads_dir
      if String.starts_with?(old_path, uploads_dir) do
        File.rm(old_path)
      end
    end
  end

  defp uploads_directory do
    Path.join([:code.priv_dir(:little_grape), "static", "uploads", "profile_pictures"])
  end

  @doc """
  Deletes the profile picture.
  """
  def delete_profile_picture(%Profile{} = profile) do
    if profile.profile_picture do
      uploads_dir = uploads_directory()
      delete_old_picture(profile, uploads_dir)

      profile
      |> Profile.profile_picture_changeset(%{profile_picture: nil})
      |> Repo.update()
    else
      {:ok, profile}
    end
  end

  @required_profile_fields [
    {:profile_picture, "Profile photo"},
    {:first_name, "First name"},
    {:birthdate, "Birthdate"},
    {:gender, "Gender"},
    {:preferred_gender, "Gender preference"}
  ]

  @doc """
  Checks if a profile has all required fields completed.

  Required fields: profile_picture, first_name, birthdate, gender, preferred_gender

  ## Examples

      iex> profile_complete?(nil)
      false

      iex> profile_complete?(%Profile{profile_picture: "pic.jpg", first_name: "Jane", ...})
      true

  """
  def profile_complete?(nil), do: false

  def profile_complete?(%Profile{} = profile) do
    Enum.all?(@required_profile_fields, fn {field, _label} ->
      Map.get(profile, field) != nil
    end)
  end

  @doc """
  Returns a list of human-readable names for missing profile fields.

  ## Examples

      iex> missing_profile_fields(%Profile{first_name: nil, birthdate: ~D[2000-01-01]})
      ["First name", ...]

  """
  def missing_profile_fields(nil) do
    Enum.map(@required_profile_fields, fn {_field, label} -> label end)
  end

  def missing_profile_fields(%Profile{} = profile) do
    @required_profile_fields
    |> Enum.filter(fn {field, _label} -> Map.get(profile, field) == nil end)
    |> Enum.map(fn {_field, label} -> label end)
  end
end
