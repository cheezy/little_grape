defmodule LittleGrapeWeb.ProfileOptions do
  @moduledoc """
  Human-readable, translated labels for profile option codes shared
  between LiveViews and controller HTML.
  """
  use Gettext, backend: LittleGrapeWeb.Gettext

  @doc """
  Translates a language code to its display label.

  Unknown codes pass through unchanged.
  """
  def translate_language("sq"), do: gettext("Albanian")
  def translate_language("en"), do: gettext("English")
  def translate_language("it"), do: gettext("Italian")
  def translate_language("de"), do: gettext("German")
  def translate_language("fr"), do: gettext("French")
  def translate_language("sr"), do: gettext("Serbian")
  def translate_language("mk"), do: gettext("Macedonian")
  def translate_language("tr"), do: gettext("Turkish")
  def translate_language("other"), do: gettext("Other")
  def translate_language(code), do: code
end
