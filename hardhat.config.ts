import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

// Audit repo — compile/test only. No networks, accounts, or secrets here.
const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      { version: "0.8.20" },
      {
        version: "0.8.28",
        settings: {
          viaIR: true,
          optimizer: { enabled: true, runs: 200 },
        },
      },
    ],
  },
};

export default config;
