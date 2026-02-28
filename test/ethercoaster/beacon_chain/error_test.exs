defmodule Ethercoaster.BeaconChain.ErrorTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.Error

  describe "Error exception" do
    test "can be created with all fields" do
      error = %Error{status: 404, code: 1, message: "Not Found"}

      assert error.status == 404
      assert error.code == 1
      assert error.message == "Not Found"
    end

    test "implements Exception.message/1" do
      error = %Error{status: 500, message: "Internal Server Error"}
      assert Exception.message(error) == "Internal Server Error"
    end

    test "can be raised" do
      assert_raise Error, "something went wrong", fn ->
        raise %Error{message: "something went wrong"}
      end
    end

    test "can be raised with raise/2 syntax" do
      assert_raise Error, "bad request", fn ->
        raise Error, message: "bad request"
      end
    end

    test "supports pattern matching in error tuples" do
      result = {:error, %Error{status: 400, code: 2, message: "Bad Request"}}

      assert {:error, %Error{status: 400, message: msg}} = result
      assert msg == "Bad Request"
    end

    test "defaults to nil for optional fields" do
      error = %Error{message: "oops"}

      assert error.status == nil
      assert error.code == nil
    end
  end
end
