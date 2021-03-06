defmodule Explorer.SmartContract.VerifierTest do
  use ExUnit.Case, async: true
  use Explorer.DataCase

  doctest Explorer.SmartContract.Verifier

  alias Explorer.SmartContract.Verifier
  alias Explorer.Factory

  describe "evaluate_authenticity/2" do
    setup do
      {:ok, contract_code_info: Factory.contract_code_info()}
    end

    test "verifies the generated bytecode against bytecode retrieved from the blockchain", %{
      contract_code_info: contract_code_info
    } do
      contract_address = insert(:contract_address, contract_code: contract_code_info.bytecode)

      params = %{
        "contract_source_code" => contract_code_info.source_code,
        "compiler_version" => contract_code_info.version,
        "name" => contract_code_info.name,
        "optimization" => contract_code_info.optimized
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "verifies the generated bytecode with external libraries" do
      contract_data =
        "#{File.cwd!()}/test/support/fixture/smart_contract/compiler_tests.json"
        |> File.read!()
        |> Jason.decode!()
        |> List.first()

      compiler_version = contract_data["compiler_version"]
      external_libraries = contract_data["external_libraries"]
      name = contract_data["name"]
      optimize = contract_data["optimize"]
      contract = contract_data["contract"]
      expected_bytecode = contract_data["expected_bytecode"]

      contract_address = insert(:contract_address, contract_code: "0x" <> expected_bytecode)

      params = %{
        "contract_source_code" => contract,
        "compiler_version" => compiler_version,
        "name" => name,
        "optimization" => optimize,
        "external_libraries" => external_libraries
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "verifies smart contract with constructor arguments", %{
      contract_code_info: contract_code_info
    } do
      contract_address = insert(:contract_address, contract_code: contract_code_info.bytecode)

      constructor_arguments = "0102030405"

      params = %{
        "contract_source_code" => contract_code_info.source_code,
        "compiler_version" => contract_code_info.version,
        "name" => contract_code_info.name,
        "optimization" => contract_code_info.optimized,
        "constructor_arguments" => constructor_arguments
      }

      :transaction
      |> insert(
        created_contract_address_hash: contract_address.hash,
        input: contract_code_info.bytecode <> constructor_arguments
      )
      |> with_block()

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "tries to compile with the latest evm version if wrong evm version was provided" do
      bytecode =
        "0x60606040526000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff168063256fec88146100545780633fa4f245146100a9578063812600df146100d2575b600080fd5b341561005f57600080fd5b6100676100f5565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b34156100b457600080fd5b6100bc61011b565b6040518082815260200191505060405180910390f35b34156100dd57600080fd5b6100f36004808035906020019091905050610121565b005b600160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b60005481565b806000540160008190555033600160006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505b505600a165627a7a72305820b81379d1ae9d8e0fde05ee02b8bd170f43f8bd3d54da8b7ec203434a23a298980029"

      contract_address = insert(:contract_address, contract_code: bytecode)

      code = """
      pragma solidity ^0.4.15;
      contract Incrementer {
          event Incremented(address indexed sender, uint256 newValue);
          uint256 public value;
          address public lastSender;
          function Incrementer(uint256 initialValue) {
              value = initialValue;
              lastSender = msg.sender;
          }
          function inc(uint256 delta) {
              value = value + delta;
              lastSender = msg.sender;
          }
      }
      """

      params = %{
        "contract_source_code" => code,
        "compiler_version" => "v0.4.15+commit.bbb8e64f",
        "evm_version" => "homestead",
        "name" => "Incrementer",
        "optimization" => false
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "returns error when bytecode doesn't match", %{contract_code_info: contract_code_info} do
      contract_address = insert(:contract_address, contract_code: contract_code_info.bytecode)

      different_code = "pragma solidity ^0.4.24; contract SimpleStorage {}"

      params = %{
        "contract_source_code" => different_code,
        "compiler_version" => contract_code_info.version,
        "name" => contract_code_info.name,
        "optimization" => contract_code_info.optimized
      }

      response = Verifier.evaluate_authenticity(contract_address.hash, params)

      assert {:error, :generated_bytecode} = response
    end

    test "returns error when there is a compilation problem", %{contract_code_info: contract_code_info} do
      contract_address = insert(:contract_address, contract_code: contract_code_info.bytecode)

      params = %{
        "contract_source_code" => "pragma solidity ^0.4.24; contract SimpleStorage { ",
        "compiler_version" => contract_code_info.version,
        "name" => contract_code_info.name,
        "optimization" => contract_code_info.optimized
      }

      assert {:error, :compilation} = Verifier.evaluate_authenticity(contract_address.hash, params)
    end
  end

  describe "extract_bytecode/1" do
    test "extracts the bytecode from the hash" do
      code =
        "0x608060405234801561001057600080fd5b5060df8061001f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600a165627a7a723058203c381c1b48b38d050c54d7ef296ecd411040e19420dfec94772b9c49ae106a0b0029"

      swarm_source = "3c381c1b48b38d050c54d7ef296ecd411040e19420dfec94772b9c49ae106a0b"

      bytecode =
        "0x608060405234801561001057600080fd5b5060df8061001f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600"

      assert bytecode == Verifier.extract_bytecode(code)
      assert bytecode != code
      assert String.contains?(code, bytecode) == true
      assert String.contains?(bytecode, "0029") == false
      assert String.contains?(bytecode, swarm_source) == false
    end

    test "extracts everything to the left of the swarm hash" do
      code =
        "0x608060405234801561001057600080fd5b5060df80610010029f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600a165627a7a723058203c381c1b48b38d050c54d7ef296ecd411040e19420dfec94772b9c49ae106a0b0029"

      swarm_source = "3c381c1b48b38d050c54d7ef296ecd411040e19420dfec94772b9c49ae106a0b"

      bytecode =
        "0x608060405234801561001057600080fd5b5060df80610010029f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600"

      assert bytecode == Verifier.extract_bytecode(code)
      assert bytecode != code
      assert String.contains?(code, bytecode) == true
      assert String.contains?(bytecode, "0029") == true
      assert String.contains?(bytecode, swarm_source) == false
    end
  end
end
