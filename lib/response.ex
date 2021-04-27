defmodule Webmentions.Response do
  defstruct [:status, :http_status, :target, :endpoint, :message, :body]
end
