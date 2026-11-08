Bug:  GeometryPoint lat/lng swap issue
### Describe the bug

When viewing the coordinates in Surrealist, it would appear as if the coordinates are the wrong way around. I assume this is an issue with the GO SDK.

From what I understand from the docs, GeometryPoint is (longitude, latitude) https://surrealdb.com/docs/surrealql/datamodel/geometries#point

Yet when I create a record with the correct cooirdinates via GO SDK, when I view the geometry map within Surrealist e.g. Geography explorer, it's in the wrong location. I have to flip the coordinates in order to get it to work.

### Steps to reproduce

```
package main

import (
	"fmt"
	"log"

	"github.com/surrealdb/surrealdb.go"
	"github.com/surrealdb/surrealdb.go/pkg/models"
)

// Location represents a geographic location
type Location struct {
	ID          *models.RecordID      `json:"id,omitempty"`
	Name        string                `json:"name"`
	Coordinates *models.GeometryPoint `json:"coordinates"`
}

func main() {
	// Connect to SurrealDB
	db, err := surrealdb.New("ws://localhost:8530")
	if err != nil {
		log.Fatalf("Failed to connect to SurrealDB: %v", err)
	}
	defer db.Close()

	// Authenticate (adjust credentials as needed)
	authData := &surrealdb.Auth{
		Username: "root",
		Password: "root",
	}
	if _, err := db.SignIn(authData); err != nil {
		log.Fatalf("Failed to authenticate: %v", err)
	}

	// Use namespace and database
	if err := db.Use("test", "test"); err != nil {
		log.Fatalf("Failed to use namespace/database: %v", err)
	}

	fmt.Println("=== Testing GeometryPoint Coordinate Bug ===")
	fmt.Println()

	// Test Case 1: Create location with standard lat/lng values
	fmt.Println("Test Case 1: Creating location with standard coordinates")
	fmt.Println("---------------------------------------------------")

	london1 := Location{
		Name: "London1",
		Coordinates: &models.GeometryPoint{
			Latitude:  51.5074, // London latitude
			Longitude: -0.1278, // London longitude
		},
	}

	// Create the record
	created, err := surrealdb.Create[Location](db, models.Table("locations"), london1)
	if err != nil {
		log.Fatalf("Failed to create location: %v", err)
	}

	// Test Case 2: Verify the bug by creating with swapped coordinates
	fmt.Println("Test Case 2: Creating location with SWAPPED coordinates (workaround)")
	fmt.Println("-------------------------------------------------------------------")

	london2 := Location{
		Name: "London2",
		Coordinates: &models.GeometryPoint{
			Latitude:  -0.1278, // London longitude
			Longitude: 51.5074, // London latitude
		},
	}

	created2, err := surrealdb.Create[Location](db, models.Table("locations"), london2)
	if err != nil {
		log.Fatalf("Failed to create location: %v", err)
	}

	fmt.Println(created, created2)
}

```

### Expected behaviour

For now I simply just swap them in code, but it's a bit confusing.

I've tested on the very latest GO SDK 0.3.3.

### SurrealDB version

2.3.6

### Contact Details

_No response_

### Is there an existing issue for this?

- [x] I have searched the existing issues

### Code of Conduct

- [x] I agree to follow this project's Code of Conduct
