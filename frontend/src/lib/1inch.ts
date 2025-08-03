import axios from 'axios';

export const get1inchSwapData = async (params: {
  fromToken: string;
  toToken: string;
  amount: string;
  chainId: number;
}) => {
  const { data } = await axios.get(
    `https://api.1inch.io/v5.0/${params.chainId}/swap`,
    {
      params: {
        fromTokenAddress: params.fromToken,
        toTokenAddress: params.toToken,
        amount: params.amount,
        slippage: 1,
        disableEstimate: true // Faster for demo
      }
    }
  );
  return data;
};

export const createLimitOrder = async (order: any) => {
  // Use 1inch SDK or direct API
  const { data } = await axios.post(
    'https://limit-orders.1inch.io/v3.0/1/limit-order',
    order
  );
  return data;
};