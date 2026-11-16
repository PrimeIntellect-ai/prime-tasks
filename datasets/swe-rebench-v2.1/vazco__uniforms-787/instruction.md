Typescript mismatch error on rc-2
I'm trying to build a form using AutoForm from a bare bones schema, I think I have a very minimal example:

```
import { buildASTSchema, parse } from "graphql";
import React from "react";
import { AutoForm } from "uniforms-bootstrap4";
import { GraphQLBridge } from "uniforms-bridge-graphql";

type CustomerUpdateAutoFormProps = {};
export const CustomerUpdateAutoForm: React.SFC<CustomerUpdateAutoFormProps> = ({}) => {
  const schema = `    type Author {
    id:        String!
    firstName: String
    lastName:  String
}

type Post {
    id:     Int!
    author: Author!
    title:  String
    votes:  Int
}
`;
  const astSchema = buildASTSchema(parse(schema));
  const schemaType = astSchema.getType("Post");
  const schemaValidator = () => {};
  const bridge = new GraphQLBridge(schemaType!, schemaValidator);
  return <AutoForm schema={bridge} onSubmit={console.log} />;
};
```

But it results in the follow error:
```
TypeScript error in /home/pljns/Desktop/picket-frontend/src/components/administrator/customer/CustomerUpdateAutoForm.tsx(24,36):
Argument of type 'GraphQLNamedType' is not assignable to parameter of type 'GraphQLInputObjectType | GraphQLObjectType<any, any, { [key: string]: any; }>'.
  Type 'GraphQLScalarType' is not assignable to type 'GraphQLInputObjectType | GraphQLObjectType<any, any, { [key: string]: any; }>'.
    Type 'GraphQLScalarType' is missing the following properties from type 'GraphQLObjectType<any, any, { [key: string]: any; }>': isTypeOf, getFields, getInterfaces  TS2345

    22 |   const schemaType = astSchema.getType("Post");
    23 |   const schemaValidator = () => {};
  > 24 |   const bridge = new GraphQLBridge(schemaType!, schemaValidator);
       |                                    ^
    25 |   return <AutoForm schema={bridge} onSubmit={console.log} />;
    26 | };
    27 |
```

It's because typescript seems to be expecting ` isTypeOf, getFields, getInterfaces`, why is that? Is there a version of Graphql that does work? I'm using 15.3.0.

My package.json file:

```
{
  "name": "client",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "@apollo/client": "^3.0.1",
    "@mapbox/polyline": "^1.1.1",
    "@stripe/stripe-js": "^1.5.0",
    "@testing-library/jest-dom": "^5.11.1",
    "@testing-library/react": "^10.4.7",
    "@testing-library/user-event": "^12.0.11",
    "@types/jest": "^26.0.5",
    "@types/jquery": "^3.5.0",
    "@types/mapbox-gl": "^1.11.1",
    "@types/node": "^14.0.23",
    "@types/react": "^16.9.0",
    "@types/react-big-calendar": "^0.24.2",
    "@types/react-bootstrap": "^1.0.1",
    "@types/react-bootstrap-typeahead": "^3.4.6",
    "@types/react-datepicker": "^3.0.2",
    "@types/react-dom": "^16.9.0",
    "@types/react-map-gl": "^5.2.5",
    "@types/react-router-dom": "^5.1.3",
    "@types/yup": "^0.29.3",
    "babel-plugin-import": "^1.13.0",
    "bootstrap": "^4.4.1",
    "chart.js": "^2.9.3",
    "customize-cra": "^1.0.0",
    "date-fns": "^2.14.0",
    "dotenv": "^8.2.0",
    "formik": "^2.1.4",
    "graphql": "^15.3.0",
    "mapbox-gl": "^1.11.1",
    "moment": "^2.26.0",
    "node-sass": "^4.13.1",
    "react": "^16.13.0",
    "react-big-calendar": "^0.26.0",
    "react-bootstrap": "^1.0.0-beta.17",
    "react-bootstrap-typeahead": "^5.1.0",
    "react-chartjs-2": "^2.9.0",
    "react-datepicker": "^3.1.3",
    "react-dom": "^16.13.0",
    "react-icons": "^3.9.0",
    "react-json-view": "^1.19.1",
    "react-map-gl": "^5.2.7",
    "react-phone-input-2": "^2.13.5",
    "react-router-dom": "^5.1.2",
    "react-scripts": "3.4.1",
    "typescript": "~3.9.7",
    "uniforms": "^3.0.0-rc.2",
    "uniforms-bootstrap4": "^3.0.0-rc.2",
    "uniforms-bridge-graphql": "^3.0.0-rc.2",
    "yup": "^0.29.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject",
    "build-fragment": "node src/schemaQuery.js",
    "generate": "get-graphql-schema http://localhost:4000/graphql > ./src/graphql/schema.gql && gqlg --schemaFilePath ./src/graphql/schema.gql --destDirPath ./src/graphql/queries/ --depthLimit=3 && graphql-codegen --config codegen.js"
  },
  "eslintConfig": {
    "extends": "react-app"
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "devDependencies": {
    "@graphql-codegen/cli": "^1.12.2",
    "@graphql-codegen/typescript": "^1.12.2",
    "@graphql-codegen/typescript-operations": "^1.12.2",
    "@graphql-codegen/typescript-react-apollo": "^1.12.2",
    "get-graphql-schema": "^2.1.2",
    "gql-generator": "^1.0.12"
  }
}
```

Is this fixed by the latest commit? Is there a way I can specify this in my package.json file? When will the next release be?

I really like your idea and look forward to getting it working one way or another in the coming days, thank you for any help.
