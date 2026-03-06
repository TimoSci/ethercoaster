defmodule Ethercoaster.ServiceValidator do
  use Ecto.Schema

  @primary_key false
  schema "services_validators" do
    belongs_to :service, Ethercoaster.Service
    belongs_to :validator, Ethercoaster.ValidatorRecord
  end
end
