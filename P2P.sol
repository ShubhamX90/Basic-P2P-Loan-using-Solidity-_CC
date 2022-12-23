// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

/*
*Here we have assumed that the currency for loan exchange and the currency for the collateral amount will be 
same which is not true in real life
*We have also considered the interest rate to be fixed at 10 percent
*/

contract P2P 
{
 struct Terms 
 {
     //The amount of IERC20 tokens to be lended
     uint256 loanAmount;
     //Interest rate of loaned amount
     uint256 interestRate;
     //Collateral amount, predefined, should be more valuable than the loanAmount+interest at any time
     uint256 collateralAmount;
     //Timestamp by which the loan should be repayed.After it the lender can liquidate the loan
     uint256 repayTimestamp;
     //initial timestamp of the block
     uint256 initialTimestamp;
 }
Terms public terms;

//The loan can be in 5 states. Created, Funded, Taken, Repayed, Liquidated
//in repayed and liquidated states the loan will be destroyed
enum LoanState {Created, Funded, Taken}
LoanState public state;

//Modifier that prevents some functions to be called in any other state than the current state
modifier onlyInState(LoanState expectedState)
{
    require(state == expectedState, "Not allowed in this state");
    _;
}

address payable public lenderAddr;
address payable public borrowerAddr;
address public IERC20Addr;
address public collateralAddr;


constructor(Terms memory _terms, address _IERC20Addr, address _collateralAddr)
{
    terms = _terms;
    IERC20Addr = _IERC20Addr;
    lenderAddr = payable(msg.sender);
    collateralAddr =_collateralAddr ;

    //fixing interest rate to 10 percent
    terms.interestRate=10;

    //Loan is now created
    state = LoanState.Created;
}

function provideCollateral() public onlyInState(LoanState.Created)
{
    //Transfer collateral amount from borrower's address to intermediate address for collateral amount for loan
    IERC20(collateralAddr).transferFrom(msg.sender, address(this), terms.collateralAmount);
    borrowerAddr = payable(msg.sender);
}

function fundLoan() public onlyInState(LoanState.Created)
{
    //fundLoan() transfers tokens from the lender to the contract so that we can later transfer it to the borrower as a loan
    state = LoanState.Funded;
    
    //checking if the amount to be lended by the lender excceds his/her cureent balance 
    require(msg.value > IERC20(IERC20Addr).balanceOf(msg.sender), "Amount to be lended excceds current balance");
    
    //Transfer loan amount from lender's address to intermediate address for loan amount
    IERC20(IERC20Addr).transferFrom(msg.sender, address(this), terms.loanAmount);
    //storing initial timestamp of the block i.e. timestamp of sanctioning of loan
    terms.initialTimestamp = block.timestamp;
}

function acceptAndCheckTerms() public payable onlyInState(LoanState.Funded)
{   
    //The Collateral amount should be greater than the amount to be lended else the loan will not be sanctioned
    require(msg.value >= terms.collateralAmount, "Invalid collateral amount" );

    //Changing state of loan to Taken
    state = LoanState.Taken;
    
    //Transfering the loan amount from the intermediate address to borrower's address
    IERC20(IERC20Addr).transfer(borrowerAddr, terms.loanAmount);
}

function repay() public onlyInState(LoanState.Taken)
{   
    //checking that the person repaying the loan is the borrower
    require(msg.sender == borrowerAddr, "Only the borrower can repay the loan");

    uint256 interest;
    uint256 amt = terms.loanAmount;

    uint256 numDays = block.timestamp - terms.initialTimestamp;
    
    //calculating the final amount after compounding
    for(uint i=0; i <= numDays; i++)
    {
    interest = interest + (terms.interestRate*amt);
    }
    terms.loanAmount += interest;
    
    //Transfering the loaned amount + total interest from borrower's address back to the lender's address through the intermediate address
    IERC20(IERC20Addr).transferFrom(borrowerAddr, lenderAddr, terms.loanAmount );

    //now the state of the loan is repayed so the loan will be destroyed
    selfdestruct(borrowerAddr);

}

function liquidate() public onlyInState(LoanState.Taken)
{   
    require(msg.sender == lenderAddr, "Only the lender can liquidate the loan");

    //If the time limit for repayment of the loan has been crossed the the loan will automatically be liquidated
    require(block.timestamp >= terms.repayTimestamp, "Can not liquidate before the loan is due");

    //sending the collateral amount to the lender and destroying the loan
    selfdestruct(lenderAddr);
}

}
