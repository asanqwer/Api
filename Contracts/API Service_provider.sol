// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title API Service Provider Platform
 * @dev A decentralized platform for API service providers and consumers
 * @author API Service Provider Team
 */
contract Project {
    
    // Struct to represent an API service
    struct APIService {
        uint256 serviceId;
        address provider;
        string serviceName;
        string description;
        uint256 pricePerCall;
        uint256 totalCalls;
        bool isActive;
        uint256 createdAt;
    }
    
    // Struct to represent a service subscription
    struct Subscription {
        uint256 subscriptionId;
        address consumer;
        uint256 serviceId;
        uint256 callsRemaining;
        uint256 expiresAt;
        bool isActive;
    }
    
    // State variables
    mapping(uint256 => APIService) public apiServices;
    mapping(uint256 => Subscription) public subscriptions;
    mapping(address => uint256[]) public providerServices;
    mapping(address => uint256[]) public consumerSubscriptions;
    
    uint256 public nextServiceId;
    uint256 public nextSubscriptionId;
    uint256 public platformFeePercentage; // Fee in basis points (100 = 1%)
    address public owner;
    
    // Events
    event ServiceRegistered(
        uint256 indexed serviceId,
        address indexed provider,
        string serviceName,
        uint256 pricePerCall
    );
    
    event ServiceSubscribed(
        uint256 indexed subscriptionId,
        address indexed consumer,
        uint256 indexed serviceId,
        uint256 callsPurchased
    );
    
    event APICallMade(
        uint256 indexed subscriptionId,
        address indexed consumer,
        uint256 indexed serviceId,
        uint256 callsRemaining
    );
    
    event ServiceDeactivated(uint256 indexed serviceId);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyServiceProvider(uint256 _serviceId) {
        require(
            apiServices[_serviceId].provider == msg.sender,
            "Only service provider can call this function"
        );
        _;
    }
    
    modifier serviceExists(uint256 _serviceId) {
        require(
            apiServices[_serviceId].provider != address(0),
            "Service does not exist"
        );
        _;
    }
    
    modifier subscriptionExists(uint256 _subscriptionId) {
        require(
            subscriptions[_subscriptionId].consumer != address(0),
            "Subscription does not exist"
        );
        _;
    }
    
    /**
     * @dev Constructor to initialize the contract
     */
    constructor() {
        owner = msg.sender;
        nextServiceId = 1;
        nextSubscriptionId = 1;
        platformFeePercentage = 250; // 2.5% platform fee
    }
    
    /**
     * @dev Core Function 1: Register a new API service
     * @param _serviceName Name of the API service
     * @param _description Description of the API service
     * @param _pricePerCall Price per API call in wei
     */
    function registerService(
        string memory _serviceName,
        string memory _description,
        uint256 _pricePerCall
    ) external returns (uint256) {
        require(bytes(_serviceName).length > 0, "Service name cannot be empty");
        require(_pricePerCall > 0, "Price per call must be greater than 0");
        
        uint256 serviceId = nextServiceId;
        
        apiServices[serviceId] = APIService({
            serviceId: serviceId,
            provider: msg.sender,
            serviceName: _serviceName,
            description: _description,
            pricePerCall: _pricePerCall,
            totalCalls: 0,
            isActive: true,
            createdAt: block.timestamp
        });
        
        providerServices[msg.sender].push(serviceId);
        nextServiceId++;
        
        emit ServiceRegistered(serviceId, msg.sender, _serviceName, _pricePerCall);
        
        return serviceId;
    }
    
    /**
     * @dev Core Function 2: Subscribe to an API service
     * @param _serviceId ID of the service to subscribe to
     * @param _callCount Number of API calls to purchase
     * @param _durationDays Subscription duration in days
     */
    function subscribeToService(
        uint256 _serviceId,
        uint256 _callCount,
        uint256 _durationDays
    ) external payable serviceExists(_serviceId) returns (uint256) {
        require(apiServices[_serviceId].isActive, "Service is not active");
        require(_callCount > 0, "Call count must be greater than 0");
        require(_durationDays > 0, "Duration must be greater than 0");
        
        uint256 totalCost = apiServices[_serviceId].pricePerCall * _callCount;
        require(msg.value >= totalCost, "Insufficient payment");
        
        uint256 subscriptionId = nextSubscriptionId;
        uint256 expiresAt = block.timestamp + (_durationDays * 1 days);
        
        subscriptions[subscriptionId] = Subscription({
            subscriptionId: subscriptionId,
            consumer: msg.sender,
            serviceId: _serviceId,
            callsRemaining: _callCount,
            expiresAt: expiresAt,
            isActive: true
        });
        
        consumerSubscriptions[msg.sender].push(subscriptionId);
        nextSubscriptionId++;
        
        // Calculate platform fee and provider payment
        uint256 platformFee = (totalCost * platformFeePercentage) / 10000;
        uint256 providerPayment = totalCost - platformFee;
        
        // Transfer payment to provider
        payable(apiServices[_serviceId].provider).transfer(providerPayment);
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
        
        emit ServiceSubscribed(subscriptionId, msg.sender, _serviceId, _callCount);
        
        return subscriptionId;
    }
    
    /**
     * @dev Core Function 3: Make an API call (decrement usage)
     * @param _subscriptionId ID of the subscription to use
     */
    function makeAPICall(uint256 _subscriptionId) 
        external 
        subscriptionExists(_subscriptionId) 
    {
        Subscription storage subscription = subscriptions[_subscriptionId];
        
        require(subscription.consumer == msg.sender, "Only subscriber can make API calls");
        require(subscription.isActive, "Subscription is not active");
        require(subscription.callsRemaining > 0, "No calls remaining");
        require(block.timestamp <= subscription.expiresAt, "Subscription has expired");
        
        subscription.callsRemaining--;
        apiServices[subscription.serviceId].totalCalls++;
        
        // Deactivate subscription if no calls remaining
        if (subscription.callsRemaining == 0) {
            subscription.isActive = false;
        }
        
        emit APICallMade(
            _subscriptionId,
            msg.sender,
            subscription.serviceId,
            subscription.callsRemaining
        );
    }
    
    /**
     * @dev Deactivate a service (only by provider)
     * @param _serviceId ID of the service to deactivate
     */
    function deactivateService(uint256 _serviceId) 
        external 
        serviceExists(_serviceId) 
        onlyServiceProvider(_serviceId) 
    {
        apiServices[_serviceId].isActive = false;
        emit ServiceDeactivated(_serviceId);
    }
    
    /**
     * @dev Get service details
     * @param _serviceId ID of the service
     */
    function getService(uint256 _serviceId) 
        external 
        view 
        serviceExists(_serviceId) 
        returns (APIService memory) 
    {
        return apiServices[_serviceId];
    }
    
    /**
     * @dev Get subscription details
     * @param _subscriptionId ID of the subscription
     */
    function getSubscription(uint256 _subscriptionId) 
        external 
        view 
        subscriptionExists(_subscriptionId) 
        returns (Subscription memory) 
    {
        return subscriptions[_subscriptionId];
    }
    
    /**
     * @dev Get services by provider
     * @param _provider Address of the provider
     */
    function getServicesByProvider(address _provider) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return providerServices[_provider];
    }
    
    /**
     * @dev Get subscriptions by consumer
     * @param _consumer Address of the consumer
     */
    function getSubscriptionsByConsumer(address _consumer) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return consumerSubscriptions[_consumer];
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFeePercentage New fee percentage in basis points
     */
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 1000, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
    
    /**
     * @dev Withdraw platform fees (only owner)
     */
    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner).transfer(balance);
    }
    
    /**
     * @dev Transfer ownership (only owner)
     * @param _newOwner Address of the new owner
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner cannot be zero address");
        owner = _newOwner;
    }
}
