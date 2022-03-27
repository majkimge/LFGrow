import { defaultAbiCoder } from 'ethers/lib/utils';
import { task } from 'hardhat/config';
import {
    FollowNFT__factory,
    LensHub__factory,
    FixedCurrencyFeeFollowModule__factory,
} from '../typechain-types';
import { CreateProfileDataStruct } from '../typechain-types/LensHub';
import {
    deployContract,
    getAddrs,
    initEnv,
    ProtocolState,
    waitForTx,
    ZERO_ADDRESS,
} from './helpers/utils';

task('test-follow', 'tests the SecretCodeFollowModule').setAction(async ({ }, hre) => {
    const [governance, , user] = await initEnv(hre);
    const addrs = getAddrs();
    const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], governance);

    await waitForTx(lensHub.setState(ProtocolState.Unpaused));
    await waitForTx(lensHub.whitelistProfileCreator(user.address, true));
    //await waitForTx(moduleGl(user.address, true));
    //0xeAD9C93b79Ae7C1591b1FB5323BD777E86e150d4
    //0xf4e77E5Da47AC3125140c470c71cBca77B5c638c
    //0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6
    //0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
    const inputStruct: CreateProfileDataStruct = {
        to: user.address,
        handle: 'zer0dot',
        imageURI:
            'https://ipfs.fleek.co/ipfs/ghostplantghostplantghostplantghostplantghostplantghostplan',
        followModule: ZERO_ADDRESS,
        followModuleData: [],
        followNFTURI:
            'https://ipfs.fleek.co/ipfs/ghostplantghostplantghostplantghostplantghostplantghostplan',
    };
    // await waitForTx(lensHub.connect(user).createProfile(inputStruct));

    const fixedCurrencyFollowModule = await deployContract(
        new FixedCurrencyFeeFollowModule__factory(governance).deploy(lensHub.address, '0xf4e77E5Da47AC3125140c470c71cBca77B5c638c', '0xE592427A0AEce92De3Edee1F18E0157C05861564')
    );
    await waitForTx(lensHub.whitelistFollowModule(fixedCurrencyFollowModule.address, true));

    const data = defaultAbiCoder.encode(['uint256', 'address', 'address'], ["1000000", '0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6', user.address]);
    await waitForTx(lensHub.connect(user).setFollowModule(1, fixedCurrencyFollowModule.address, data));

    const badData = defaultAbiCoder.encode(['address', 'uint256'], ['0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', '100000']);

    try {
        await waitForTx(lensHub.connect(user).follow([1], [badData]));
    } catch (e) {
        console.log(`Expected failure occurred! Error: ${e}`);
    }
    const goodData = defaultAbiCoder.encode(['address', 'uint256'], ['0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', '200000000000000000000000']);
    const tx = await waitForTx(lensHub.connect(user).follow([1], [goodData]));
    console.log(tx);

    const followNFTAddr = await lensHub.getFollowNFT(1);
    const followNFT = FollowNFT__factory.connect(followNFTAddr, user);

    const totalSupply = await followNFT.totalSupply();
    const ownerOf = await followNFT.ownerOf(1);

    console.log(`Follow NFT total supply (should be 1): ${totalSupply}`);
    console.log(
        `Follow NFT owner of ID 1: ${ownerOf}, user address (should be the same): ${user.address}`
    );
});
