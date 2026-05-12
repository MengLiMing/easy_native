// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "easy_native",
	platforms: [
		.iOS("12.0")
	],
	products: [
		.library(name: "easy_native", targets: ["easy_native"])
	],
	targets: [
		.target(
			name: "easy_native",
			dependencies: [],
			resources: [
				.process("Resources")
			]
		)
	]
)
