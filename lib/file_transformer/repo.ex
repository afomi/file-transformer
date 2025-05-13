defmodule FileTransformer.Repo do
  use Ecto.Repo,
    otp_app: :file_transformer,
    adapter: Ecto.Adapters.Postgres
end
