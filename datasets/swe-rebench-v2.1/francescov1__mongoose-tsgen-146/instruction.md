Support typescript enums
Mongoose supports setting enums from a typescript enum (https://github.com/Automattic/mongoose/issues/9546), but mongoose-tsgen generates a `string` type.
```ts
import { Schema, model } from "mongoose";

enum Status {
  draft = 'draft',
  trash = 'trash',
  published = 'published',
  archive = 'archived',
}

const TestSchema = new Schema({
  status: {
    type: String,
    enum: Status,
    required: true,
  },
});
export const TestModel = model('test', TestSchema);
```

### Actual Output:
```ts
export type test = {
  status: string;
  _id: mongoose.Types.ObjectId;
};
```

### Expected Output:
```ts
export type test = {
  status: 'draft' | 'trash' | 'published' | 'archived';
  _id: mongoose.Types.ObjectId;
};
```

### Work Around:
```ts
const TestSchema = new Schema({
  status: {
    type: String,
    enum: Object.values(Status),
    required: true,
  },
});
```
