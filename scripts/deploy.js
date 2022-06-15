const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const accountBalance = await deployer.getBalance();

  console.log("Deploying contract with account: ", deployer.address);
  console.log("Account balance: ", accountBalance.toString());

  const NFTMarketplace = await hre.ethers.getContractFactory("NFTMarketplace");
  const nftMarketplace = await NFTMarketplace.deploy();
  await nftMarketplace.deployed();
  const Erc721 = await hre.ethers.getContractFactory("UITToken721");
  const erc721 = await Erc721.deploy(
    "UITToken721",
    "U721",
    nftMarketplace.address
  );
  await erc721.deployed();
  const Erc1155 = await hre.ethers.getContractFactory("UITToken1155");
  const erc1155 = await Erc1155.deploy(
    "UITToken1155",
    "U1155",
    nftMarketplace.address
  );
  await erc1155.deployed();
  const VerifySignature = await hre.ethers.getContractFactory(
    "VerifySignature"
  );
  const verifySignature = await VerifySignature.deploy();
  await verifySignature.deployed();

  console.log("ERC721:", erc721.address);
  console.log("ERC1155:", erc1155.address);
  console.log("Contract deployed to:", nftMarketplace.address);
  console.log("Verify signature: ", verifySignature.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
