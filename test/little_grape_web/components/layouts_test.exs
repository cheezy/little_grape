defmodule LittleGrapeWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias LittleGrapeWeb.Layouts

  describe "language_switcher/1" do
    test "offers every supported locale with no inline JS" do
      html = render_component(&Layouts.language_switcher/1, locale: "en")

      for code <- LittleGrapeWeb.Plugs.Locale.locales() do
        assert html =~ ~s(value="#{code}")
      end

      for label <- ["Shqip", "English", "Italiano", "Ελληνικά", "Deutsch", "Français"] do
        assert html =~ label
      end

      assert html =~ "data-locale-switcher"
      refute html =~ "onchange"
    end

    test "marks the current locale as selected" do
      html = render_component(&Layouts.language_switcher/1, locale: "de")

      assert html =~ ~s(value="de" selected)
      refute html =~ ~s(value="en" selected)
    end
  end

  describe "top_nav/1" do
    test "mobile menu toggle uses a data attribute instead of inline onclick" do
      html = render_component(&Layouts.top_nav/1, locale: "en")

      refute html =~ "onclick"
      assert html =~ "data-toggle-hidden"
    end
  end

  describe "auth_card/1" do
    test "renders the centered card shell with title, subtitle, and body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Layouts.auth_card flash={%{}} locale="en" title="Log in">
          <:subtitle>Sub text here</:subtitle>
          <p>Body content</p>
        </Layouts.auth_card>
        """)

      assert html =~ "max-w-md"
      assert html =~ "bg-white rounded-3xl shadow-2xl p-8 border border-gray-100"
      assert html =~ "Log in"
      assert html =~ "Sub text here"
      assert html =~ "Body content"
    end
  end

  describe "settings_card/1" do
    test "renders the wide card shell with divider, cross-link, and switcher" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Layouts.settings_card
          flash={%{}}
          locale="en"
          title="Change Email"
          subtitle="Update your email address"
          link_href="/users/settings/password"
          link_text="Change Password instead"
        >
          <p>Form goes here</p>
        </Layouts.settings_card>
        """)

      assert html =~ "max-w-2xl"
      assert html =~ "Change Email"
      assert html =~ "Update your email address"
      assert html =~ "border-t border-gray-200 my-8"
      assert html =~ "Change Password instead"
      assert html =~ "Form goes here"
      assert html =~ "data-locale-switcher"
    end
  end

  describe "auth_input/1" do
    test "renders label, name, value, and the shared input classes" do
      form = to_form(%{"email" => "a@b.c"}, as: "user")

      html =
        render_component(&Layouts.auth_input/1,
          field: form[:email],
          type: "email",
          label: "Email"
        )

      assert html =~ ~s(name="user[email]")
      assert html =~ ~s(value="a@b.c")
      assert html =~ "block text-gray-700 font-medium mb-2"

      assert html =~
               "w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-red-500 focus:ring-2 focus:ring-red-100 transition outline-none"
    end

    test "never echoes a password value" do
      form = to_form(%{"password" => "secret123"}, as: "user")

      html =
        render_component(&Layouts.auth_input/1,
          field: form[:password],
          type: "password",
          label: "Password"
        )

      refute html =~ "secret123"
    end

    test "renders field errors" do
      form = to_form(%{}, as: "user", errors: [email: {"is invalid", []}])

      html =
        render_component(&Layouts.auth_input/1,
          field: form[:email],
          type: "email",
          label: "Email"
        )

      assert html =~ "is invalid"
    end
  end
end
