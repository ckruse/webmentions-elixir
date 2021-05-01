defmodule Webmentions.Response do
  defstruct [:status, :http_status, :target, :endpoint, :message, :body]

  @type t :: %__MODULE__{}
end
