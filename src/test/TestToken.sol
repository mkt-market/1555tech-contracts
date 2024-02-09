import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {}

    function mint(uint256 _amount) external {
        _mint(msg.sender, _amount);
    }
}
