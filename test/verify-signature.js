const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VerifySignature", function () {
  it("Check signature", async function () {
    const accounts = await ethers.getSigners(1);
    const VerifySignature = await ethers.getContractFactory("VerifySignature");
    const contract = await VerifySignature.deploy();
    await contract.deployed();

    const signer = accounts[0];
    const message = "hello";

    const hash = await contract.getMessageHash(message);
    const sig = await signer.signMessage(ethers.utils.arrayify(hash));

    expect(await contract.verify(signer.address, message, sig)).to.equal(true);
  });
});
