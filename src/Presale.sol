// SPDX-License-Identifier: MIT

pragma solidity ^0.8.35;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "src/interfaces/IAggregator.sol";

contract Presale is Ownable {
    /*
            El primer paso es crear el SC e importar la libreria de Ownbale.

            Una vez que tenemos la librería importada creamos el constructor
            y creamos las variables, en este caso creamos las address para admitir USDT y USDC
            y también creamos la addres foundReceiver que es la dirección a la que va a ir
            el USDT y USDC que envian los usuarios y por último creamos una variable uint256[][3]
            que es como si fuera una array bidimensional de java, en este caso le ponemos un 3 pq
            vamos a tener 3 fases.

            Continuando con el desarrollo, para esta app vamos a meter dos funciones que nos
            permiten poner que un usuario pertenezca a una lista negra y así de esa manera no
            pueda comprar.
            Para ello creamos una variable mapping(address => bool) y con la variable creada
            creamos dos funciones que sean onlyOwner, para que solo las pueda ejecutar el Owner
            del SC y en una ponemos que la variable del mapping sea true y en otra false, las
            funciones que hemos creado son addToBlackList y removeFromBlackList.

            Después de hacer las funciones para añadir a la lista negra... creamos una funciones
            que nos permiten hacer una retirada de dinero de emergencia para personas que se equivoquen
            o que por algun bug o algo y se queden los tokens en el aire poder rescatarlos, para ello
            hemos creado las funciones: "emergencyERC20Withdraw" y "emergencyETHWithdraw".

            Con las funciones de retiro ya implementadas lo que vamos a hacer es añadir en nuestra presale
            el tiempo de inicio y de fin, para ello creamos dos variables globales: "uint256 public startingTime;"
            y "uint256 public endingTime;" y las inicializaremos en el constructor pasandoselas por parámetro,
            el siguiente paso será añadir una condición para comprobar que el tiempo de inicio sea menor
            que el timpo final y con esta condición ya puesta en el constructor nos vamos a la función de
            "buyWithStableCoin" que tenemos implementada para que se pueda comprar en nuestra presale y lo que hacemos
            es añadir la condición de que en caso de que el tiempo sea menor al tiempo de inicio no se podrá
            comprar.

            Ahora lo que hacemos es continuar con la función de "buyWithStableCoin" y lo que hacemos es primero
            pasarle a la función dos parámetros, el primero de tipo address para indicar el tipo de token que
            se esta pasando y el segundo un uint256 para indicar la cantidad y añadimos un "require" para indicar
            que si la address que nos esta tiene que ser o la que hemos declarado para USDT o USDC en caso contrario que
            diga que el token no es correcto.
            Y con este "require" puesto lo que hacemos es calcular la cantidad de tokens que se le van a dar a la persona
            es por ello que creamos una variable uint256 tokenAmounToReceive y añadimos un if para guardar su valor, cuando
            queremos calcular cuntos tokens se le van a proporcionar a la persona tenemos que tener en cuenta los decimales
            que tiene el token que

            Siguiendo con la funcion de "buy" lo que tenemos que hacer es guardar en una variable global la cantidad de tokens
            que se estan comprando así de esa manera añadimos la condición de que cuando se llegue al limite de tokens ya no se
            pueda comprar más.
            Después lo que hacemos es aumentar el balance de tokens del usuario, para ello lo que hacemos es crearnos una variable
            mapping(address => uint256) en la que relacionaremos la address del user que compra con una cantidad.
            Cuando hayamos hecho lo del balance, lo que tenemos que hacer es transferir a la address que hemos creado para recibir
            fondos la cantidad que nos ha pasado el usuario, para ello usamos la linea"IERC20(tokenUsedToBuy_).safeTransferFrom(
            msg.sender, foundsReceiverAddress, amount_);" como se puede ver gastamos la interfaz de IERC20 y le pasamos la address
            que ha decidido usar el user para comprar.
            De paso creamos un evento que nos dice quien es la address que ha comprado y cuanto y lo lanzamos.

            Creamos una funcion que lo que va a hacer es comprobar en que fase nos encontramos, ver la funcion checkCurrentPhase.
            y la vamos a usar dentro de la funcion de buy justo antes de guardar cuantos tokens se han vendido, pasamos en la funcion
            de comprobar phase el amount para evitar doble acounting.

            Añadimos una función extra que nos permite comprar mediante ETHER, para hacer el calculo de cuanto nos pertenece lo que hacemos
            es mediante un oráculo para extraer el precio de ETHER/USD. Para elegir ese oráculo usamos chainlink y nos fijamos en el
            contrato de ETH/USD, también obtenemos los decimales que necesitamos para calcular cuantos se van a repartir.
            Hacemos todos estos pasos porque para poder hacer la regla de 3 -> 1 token = 0.005 usd y nosotros queremos comprar con
            0.01 eth que tenemos, necesitamos igualar en decimales para poder hacer esa operación (ver como lo tenemos puesto en la
            función de "buyWithEther()").

    "
        */

    using SafeERC20 for IERC20;

    address public usdtAddress;
    address public usdcAddress;
    address public foundsReceiverAddress;
    address public dataFeedAddress;
    address public saleTokenAddress;
    uint256 public maxSellingAmount;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256[][3] public phases;

    uint256 public totalTokensSold;
    uint256 public currentPhase;

    mapping(address => bool) public isBlackListed;
    mapping(address => uint256) public userTokenBalance;

    event TokenBuy(address user, uint256 amount);

    constructor(
        address usdtAddress_,
        address usdcAddress_,
        address foundsReceiverAddress_,
        address dataFeedAddress_,
        address saleTokenAddress_,
        uint256 maxSellingAmount_,
        uint256 startingTime_,
        uint256 endingTime_,
        uint256[][3] memory phases_
    ) Ownable(msg.sender) {
        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        foundsReceiverAddress = foundsReceiverAddress_;
        dataFeedAddress = dataFeedAddress_;
        saleTokenAddress = saleTokenAddress_;
        maxSellingAmount = maxSellingAmount_;
        startingTime = startingTime_;
        endingTime = endingTime_;
        phases = phases_;

        require(startingTime < endingTime, "Incorrect presale time");
    }

    function addToBlackList(address user_) external onlyOwner {
        isBlackListed[user_] = true;
    }

    function removeFromBlackList(address user_) external onlyOwner {
        isBlackListed[user_] = false;
    }

    function buyWithStableCoin(address tokenUsedToBuy_, uint256 amount_) external {
        require(!isBlackListed[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale not starting yet");
        require(tokenUsedToBuy_ == usdtAddress || tokenUsedToBuy_ == usdcAddress, "Incorrect token");

        uint256 tokenAmountToReceive;
        if (ERC20(tokenUsedToBuy_).decimals() == 18) {
            tokenAmountToReceive = amount_ * 1e6 / phases[currentPhase][1];
        } else {
            tokenAmountToReceive = amount_ * 10 ** (ERC20(tokenUsedToBuy_).decimals()) * 1e6 / phases[currentPhase][1];
        }

        checkCurrentPhase(tokenAmountToReceive);

        totalTokensSold += tokenAmountToReceive;
        require(totalTokensSold <= maxSellingAmount, "Sold out");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, foundsReceiverAddress, amount_);

        emit TokenBuy(msg.sender, tokenAmountToReceive);
    }

    function buyWithEther() external payable {
        require(!isBlackListed[msg.sender], "User is blacklisted");
        require(block.timestamp >= startingTime && block.timestamp <= endingTime, "Presale not starting yet");

        uint256 usdValue = msg.value * getEtherPrice() / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e6 / phases[currentPhase][1];

        checkCurrentPhase(tokenAmountToReceive);

        totalTokensSold += tokenAmountToReceive;
        require(totalTokensSold <= maxSellingAmount, "Sold out");

        userTokenBalance[msg.sender] += tokenAmountToReceive;

        (bool success,) = foundsReceiverAddress.call{value: msg.value}("");
        require(success, "Transfer fail");

        emit TokenBuy(msg.sender, tokenAmountToReceive);
    }

    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) external onlyOwner {
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    function emergencyETHWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "Transfer fail");
    }

    function claim() external {
        require(block.timestamp > endingTime, "Presale not ended");

        uint256 amount = userTokenBalance[msg.sender];
        delete userTokenBalance[msg.sender];

        IERC20(saleTokenAddress).safeTransfer(msg.sender, amount);
    }

    function getEtherPrice() public view returns (uint256) {
        (, int256 price,,,) = IAggregator(dataFeedAddress).latestRoundData();
        price = price * (10 ** 10);
        return uint256(price);
    }

    function checkCurrentPhase(uint256 amount_) private returns (uint256 phase) {
        if (
            (totalTokensSold + amount_ >= phases[currentPhase][0] || (block.timestamp <= phases[currentPhase][2]))
                && currentPhase < 3
        ) {
            currentPhase++;
            phase = currentPhase;
        } else {
            phase = currentPhase;
        }
    }
}
