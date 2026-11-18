#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang git
pip3 install pytest

mkdir -p /home/user/ml_pipeline

cat << 'EOF' > /home/user/ml_pipeline/main.go
package main

import (
	"fmt"
	"math/rand"

	"gonum.org/v1/gonum/mat"
	"gonum.org/v1/gonum/stat"
)

func main() {
	rand.Seed(42)
	numSamples := 100
	numFeatures := 10
	targetDim := 3

	// Generate synthetic data
	XData := make([]float64, numSamples*numFeatures)
	YData := make([]float64, numSamples)
	for i := 0; i < numSamples; i++ {
		for j := 0; j < numFeatures; j++ {
			XData[i*numFeatures+j] = rand.NormFloat64()
		}
		// Y is a simple linear combination of the first two features plus noise
		YData[i] = 2.0*XData[i*numFeatures+0] - 1.5*XData[i*numFeatures+1] + rand.NormFloat64()*0.5
	}

	X := mat.NewDense(numSamples, numFeatures, XData)
	Y := mat.NewVecDense(numSamples, YData)

	// LEAKY PIPELINE
	// 1. Center the entire dataset
	means := make([]float64, numFeatures)
	for j := 0; j < numFeatures; j++ {
		col := mat.Col(nil, j, X)
		means[j] = stat.Mean(col, nil)
	}
	XCentered := mat.NewDense(numSamples, numFeatures, nil)
	for i := 0; i < numSamples; i++ {
		for j := 0; j < numFeatures; j++ {
			XCentered.Set(i, j, X.At(i, j)-means[j])
		}
	}

	// 2. Perform SVD on the entire dataset for PCA
	var svd mat.SVD
	ok := svd.Factorize(XCentered, mat.SVDThin)
	if !ok {
		panic("SVD failed")
	}
	var V mat.Dense
	svd.VTo(&V)

	// Projection matrix (first 'targetDim' columns of V)
	P := V.Slice(0, numFeatures, 0, targetDim)

	// 3. Project entire dataset
	XReduced := mat.NewDense(numSamples, targetDim, nil)
	XReduced.Mul(XCentered, P)

	// 4. Split Train/Test (80/20)
	trainSamples := 80
	testSamples := 20

	XTrain := XReduced.Slice(0, trainSamples, 0, targetDim)
	YTrain := Y.SliceVec(0, trainSamples)

	XTest := XReduced.Slice(trainSamples, numSamples, 0, targetDim)
	YTest := Y.SliceVec(trainSamples, numSamples)

	// 5. Train Linear Regression on Train set: w = (X^T X)^-1 X^T Y
	var XTrainT mat.Dense
	XTrainT.CloneFrom(XTrain.T())

	var XTX mat.Dense
	XTX.Mul(&XTrainT, XTrain)

	var XTXInv mat.Dense
	err := XTXInv.Inverse(&XTX)
	if err != nil {
		panic(err)
	}

	var XTY mat.VecDense
	XTY.MulVec(&XTrainT, YTrain)

	var w mat.VecDense
	w.MulVec(&XTXInv, &XTY)

	// 6. Evaluate on Test set
	var YPred mat.VecDense
	YPred.MulVec(XTest, &w)

	var mse float64
	for i := 0; i < testSamples; i++ {
		diff := YTest.AtVec(i) - YPred.AtVec(i)
		mse += diff * diff
	}
	mse /= float64(testSamples)

	fmt.Printf("%f\n", mse)
}
EOF

cd /home/user/ml_pipeline
go mod init ml_pipeline
go mod tidy

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/ml_pipeline
chmod -R 777 /home/user
