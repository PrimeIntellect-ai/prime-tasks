Required types are generated as optional
Hi, first of all I really appreciate your work. It makes working with mongoose types very easy. I am having some issues with below.

for a below schema

```typescript
import mongoose from 'mongoose';
import { UserDocument, UserModel } from './types/mongoose.gen';

const addressSchema = new mongoose.Schema(
  {
    street: {
      type: String,
      required: true,
    },
    city: {
      type: String,
      required: true,
    },
    zip: {
      type: String,
      required: true,
    },
  },
  { _id: false }
);

const schema = new mongoose.Schema(
  {
    _id: {
      type: Number,
      required: true,
    },
    billingType: {
      type: String,
      required: true,
    },
    login: {
      type: String,
      required: true,
    },
    password: {
      type: String,
      select: false,
      required: true,
    },
    category: {
      type: String,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
    email: {
      type: String,
      required: true,
    },
    billingEmail: {
      type: String,
      required: true,
    },
    phone: {
      type: String,
      required: true,
    },
    address: {
      type: addressSchema,
      required: true,
    },
    lastOnlineAt: Date,
  },
  {
    timestamps: true,
  }
);

export const Users = mongoose.model<UserDocument, UserModel>('User', schema);
```

the generated types are

```typescript

export interface User {
  _id: number;
  billingType: string;
  login: string;
  password: string;
  category: string;
  name: string;
  email: string;
  billingEmail: string;
  phone: string;
  lastOnlineAt?: Date;
  updatedAt?: Date;
  createdAt?: Date;
  address?: UserAddres;
}

```

but `address` in schema is required not optional.
