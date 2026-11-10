# Petstore API Documentation (DRAFT)

**Version:** 3.0
**Last Updated:** August 2025

## Introduction

Welcome! This document describes the Petstore API. The Petstore API lets you manage pets, orders, and users in the pet store system. It is a RESTful API.

## Base URL

```
http://petstore.swagger.io/v2
```

## Authentication

The API uses two authentication methods:

1. OAuth2 - For pet management operations
2. API Key - For store and user operations

To get an API key, please register at our developer portal.

## Pet Endpoints

### Add a New Pet

`POST /pet`

A new pet can be added to the store by sending a POST request to this endpoint. The pet object should be included in the request body.

**Request Body:**

| Field | Type | Description |
|-------|------|-------------|
| name | string | The pet's name |
| photoUrls | array | URLs of pet photos |
| category | object | Pet category |
| tags | array | Tags for the pet |
| status | string | Pet status |

**Response:** Returns the created pet object.

### Update a Pet

`PUT /pet`

Updates an existing pet. You need to send the full pet object.

### Find Pets by Status

`GET /pet/findByStatus`

You can find pets by their status using this endpoint. Pass the status as a query parameter.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| status | string | Filter by status (available, pending, sold) |

**Response:** An array of Pet objects.

### Find Pets by Tags

`GET /pet/findByTags`

Finds pets by tags. Multiple tags can be provided.

### Get a Pet by ID

`GET /pet/{petId}`

Returns a single pet. Pass the pet ID in the URL.

### Update a Pet with Form Data

`POST /pet/{petId}`

Updates a pet using form data.

### Delete a Pet

`DELETE /pet/{petId}`

Deletes a pet from the store.

### Upload a Pet Image

`POST /pet/{petId}/uploadImage`

Uploads an image for a pet. Send as multipart form data.

## Store Endpoints

### Get Inventory

`GET /store/inventory`

Returns pet inventories by status. Returns a map of status codes to quantities.

### Place an Order

`POST /store/order`

Places a new order for a pet.

**Request Body:**

| Field | Type | Description |
|-------|------|-------------|
| petId | integer | ID of the pet to order |
| quantity | integer | How many |
| shipDate | string | When to ship |
| status | string | Order status |
| complete | boolean | Whether order is complete |

### Get Order by ID

`GET /store/order/{orderId}`

Gets an order by its ID. For valid response try integer IDs with value <= 5 or > 10. Other values will generated exceptions.

### Delete an Order

`DELETE /store/order/{orderId}`

Deletes a purchase order.

## User Endpoints

### Create a User

`POST /user`

Creates a new user. This can only be done by the logged in user.

### Create Users from List

`POST /user/createWithList`

Creates list of users with given input array.

### Create Users from Array

`POST /user/createWithArray`

Creates list of users with given input array.

### Login

`GET /user/login`

Logs a user into the system. Pass username and password as query parameters.

### Logout

`GET /user/logout`

Logs out the current user.

### Get User by Username

`GET /user/{username}`

Gets user details by username.

### Update a User

`PUT /user/{username}`

Updates user information. This can only be done by the logged in user.

### Delete a User

`DELETE /user/{username}`

Deletes a user account. This can only be done by the logged in user.

## Data Models

### Pet

```json
{
  "id": 10,
  "name": "doggie",
  "category": {
    "id": 1,
    "name": "Dogs"
  },
  "photoUrls": ["https://example.com/photo.jpg"],
  "tags": [{"id": 1, "name": "friendly"}],
  "status": "available"
}
```

### Order

```json
{
  "id": 1,
  "petId": 10,
  "quantity": 1,
  "shipDate": "2025-01-15T00:00:00Z",
  "status": "placed",
  "complete": false
}
```

### User

```json
{
  "id": 1,
  "username": "john_doe",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "password": "********",
  "phone": "555-1234",
  "userStatus": 1
}
```

## Error Handling

The API returns standard HTTP error codes. If something goes wrong, you'll get an error response.

## Rate Limiting

Contact support for rate limiting information.
