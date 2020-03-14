defmodule Webmentions.Utils do
  def blank?(nil), do: true
  def blank?(""), do: true
  def blank?(0), do: true
  def blank?(false), do: true
  def blank?([]), do: true
  def blank?(map) when map == %{}, do: true
  def blank?(_), do: false

  def success?(:ok, %Tesla.Env{status: code}), do: code in 200..299
  def success?(_, _), do: false
end
